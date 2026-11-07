import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "https://ebs-pro.onrender.com",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json"
};
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: cors });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);

  try {
    const authHeader = req.headers.get("Authorization") || "";
    if (!authHeader.startsWith("Bearer ")) return reply({ error: "Authentication required" }, 401);
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceKey) return reply({ error: "Supabase server environment is not configured" }, 500);

    const callerClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false, autoRefreshToken: false } });
    const { data: authData, error: authError } = await callerClient.auth.getUser();
    if (authError || !authData.user) return reply({ error: "Invalid or expired login session" }, 401);

    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const body = await req.json();
    const tenantId = String(body.tenant_id || "");
    const email = String(body.email || "").trim().toLowerCase();
    const fullName = String(body.full_name || "").trim();
    const employeeCode = String(body.employee_code || "").trim();
    const role = String(body.role || "");
    const branchId = String(body.branch_id || "");
    const phone = String(body.phone || "").trim();
    const jobTitle = String(body.job_title || "").trim();

    if (!tenantId || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || fullName.length < 2 || !branchId) {
      return reply({ error: "Enter a valid company, email, full name and branch. Employee code is generated automatically." }, 400);
    }
    const allowed = ["admin","manager","accounts","purchase","sales","order_booker","delivery_man","warehouse","cashier","viewer"];
    if (!allowed.includes(role)) return reply({ error: "Invalid staff role. Owner access cannot be granted through staff invitations." }, 400);

    const { data: callerMembership, error: membershipError } = await admin.from("tenant_memberships")
      .select("role,is_active").eq("tenant_id", tenantId).eq("user_id", authData.user.id).maybeSingle();
    if (membershipError || !callerMembership?.is_active || !["owner","admin"].includes(callerMembership.role)) {
      return reply({ error: "Only an active owner or administrator can invite staff." }, 403);
    }
    if (callerMembership.role === "admin" && role === "admin") return reply({ error: "Only the company owner can appoint another administrator." }, 403);

    const { data: branch, error: branchError } = await admin.from("branches").select("id")
      .eq("tenant_id", tenantId).eq("id", branchId).eq("is_active", true).maybeSingle();
    if (branchError || !branch) return reply({ error: "Select an active branch belonging to this company." }, 400);

    

    const { data: users, error: usersError } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 });
    if (usersError) return reply({ error: "Could not verify the staff account. Try again." }, 500);
    let user = users.users.find((x) => x.email?.toLowerCase() === email);
    let invited = false;
    if (!user) {
      const { data: inviteData, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
        data: { full_name: fullName },
        redirectTo: "https://ebs-pro.onrender.com"
      });
      if (inviteError || !inviteData.user) return reply({ error: inviteError?.message || "Invitation email could not be sent." }, 400);
      user = inviteData.user;
      invited = true;
    }

    const { data: existingMembership, error: existingError } = await admin.from("tenant_memberships")
      .select("id").eq("tenant_id", tenantId).eq("user_id", user.id).maybeSingle();
    if (existingError) return reply({ error: "Could not verify existing company access." }, 500);
    if (existingMembership) return reply({ error: "This login is already connected to this company." }, 409);

    const { data: member, error: insertMemberError } = await admin.from("tenant_memberships")
      .insert({ tenant_id: tenantId, user_id: user.id, role, is_active: true }).select("id").single();
    if (insertMemberError) {
      if (invited) await admin.auth.admin.deleteUser(user.id);
      return reply({ error: insertMemberError.message }, 400);
    }

    const { error: employeeError } = await admin.from("employees").insert({
      tenant_id: tenantId, user_id: user.id, branch_id: branchId, employee_code: "",
      full_name: fullName, phone: phone || null, job_title: jobTitle || null, employment_status: "active"
    });
    if (employeeError) {
      await admin.from("tenant_memberships").delete().eq("id", member.id).eq("tenant_id", tenantId);
      if (invited) await admin.auth.admin.deleteUser(user.id);
      return reply({ error: employeeError.message }, 400);
    }

    const { error: profileError } = await admin.from("user_profiles").upsert({ id: user.id, full_name: fullName, phone: phone || null, updated_at: new Date().toISOString() });
    if (profileError) {
      await admin.from("employees").delete().eq("tenant_id", tenantId).eq("user_id", user.id);
      await admin.from("tenant_memberships").delete().eq("id", member.id).eq("tenant_id", tenantId);
      if (invited) await admin.auth.admin.deleteUser(user.id);
      return reply({ error: "The staff profile could not be saved. No company access was retained; please try again." }, 500);
    }
    return reply({ success: true, email, role, invited, message: invited ? "Staff invitation sent and company access configured." : "Existing login linked to the company and employee profile." });
  } catch (error) {
    return reply({ error: error instanceof Error ? error.message : "Staff invitation failed." }, 500);
  }
});
