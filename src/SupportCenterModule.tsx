import { FormEvent, useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import "./support-center.css";

type Ticket = { id:string; tenant_id:string; subject:string; category:string; priority:string; status:string; description:string; created_at:string; updated_at:string };
type Message = { id:number; ticket_id:string; sender_id:string; body:string; created_at:string };

export default function SupportCenterModule({db,tenantId,userId}:{db:SupabaseClient;tenantId:string;userId:string}) {
  const [tickets,setTickets]=useState<Ticket[]>([]);
  const [selected,setSelected]=useState("");
  const [messages,setMessages]=useState<Message[]>([]);
  const [subject,setSubject]=useState("");
  const [category,setCategory]=useState("technical");
  const [priority,setPriority]=useState("normal");
  const [description,setDescription]=useState("");
  const [reply,setReply]=useState("");
  const [creating,setCreating]=useState(false);
  const [busy,setBusy]=useState(false);
  const [notice,setNotice]=useState("");

  async function loadTickets(){
    const {data,error}=await db.from("platform_support_tickets").select("id,tenant_id,subject,category,priority,status,description,created_at,updated_at").eq("tenant_id",tenantId).order("updated_at",{ascending:false}).limit(100);
    if(error){setNotice(error.message);return;}
    setTickets((data||[]) as Ticket[]);
    if(selected && !(data||[]).some((row:any)=>row.id===selected))setSelected("");
    if(!selected && data?.length)setSelected(data[0].id);
  }
  useEffect(()=>{void loadTickets();},[tenantId]);
  useEffect(()=>{
    if(!selected){setMessages([]);return;}
    let live=true;
    db.from("platform_support_messages").select("id,ticket_id,sender_id,body,created_at").eq("ticket_id",selected).order("created_at")
      .then(({data,error})=>{if(!live)return;if(error)setNotice(error.message);else setMessages((data||[]) as Message[]);});
    return()=>{live=false;};
  },[selected,tenantId]);
  const active=tickets.find(ticket=>ticket.id===selected)||null;

  async function createTicket(event:FormEvent){
    event.preventDefault();setBusy(true);setNotice("");
    try{
      const {data,error}=await db.from("platform_support_tickets").insert({tenant_id:tenantId,created_by:userId,subject:subject.trim(),category,priority,description:description.trim(),status:"open"}).select("id,tenant_id,subject,category,priority,status,description,created_at,updated_at").single();
      if(error)throw error;
      setTickets(current=>[data as Ticket,...current]);setSelected(data.id);setSubject("");setDescription("");setCreating(false);setNotice("Support request submitted successfully.");
    }catch(error){setNotice(error instanceof Error?error.message:"Support request could not be submitted.");}
    finally{setBusy(false);}
  }
  async function sendReply(event:FormEvent){
    event.preventDefault();if(!active||!reply.trim())return;setBusy(true);setNotice("");
    try{
      const {data,error}=await db.from("platform_support_messages").insert({ticket_id:active.id,sender_id:userId,body:reply.trim()}).select("id,ticket_id,sender_id,body,created_at").single();
      if(error)throw error;setMessages(current=>[...current,data as Message]);setReply("");setNotice("Message sent to support.");
      await db.from("platform_support_tickets").update({updated_at:new Date().toISOString()}).eq("id",active.id);
    }catch(error){setNotice(error instanceof Error?error.message:"Message could not be sent.");}
    finally{setBusy(false);}
  }
  return <section className="tenant-support">
    <div className="tenant-support-head"><div><small>CUSTOMER SERVICE</small><h2>Support Center</h2><p>Submit an issue, track progress and communicate with the EBS PRO support team.</p></div><div><button onClick={()=>void loadTickets()}>↻ Refresh</button><button className="tenant-support-primary" onClick={()=>setCreating(value=>!value)}>＋ New support request</button></div></div>
    {notice&&<div className="tenant-support-notice">{notice}</div>}
    {creating&&<form className="tenant-support-form" onSubmit={createTicket}><h3>Tell us what you need help with</h3><label>Subject<input required maxLength={180} value={subject} onChange={event=>setSubject(event.target.value)} placeholder="Short summary of the issue"/></label><div className="tenant-support-grid"><label>Category<select value={category} onChange={event=>setCategory(event.target.value)}><option value="technical">Technical issue</option><option value="account">Account & access</option><option value="data">Data / transaction issue</option><option value="training">Training request</option><option value="feature">Feature request</option><option value="other">Other</option></select></label><label>Priority<select value={priority} onChange={event=>setPriority(event.target.value)}><option value="low">Low</option><option value="normal">Normal</option><option value="high">High</option><option value="critical">Critical</option></select></label></div><label>Details<textarea required rows={4} maxLength={8000} value={description} onChange={event=>setDescription(event.target.value)} placeholder="Explain what happened, where it happened and what you expected."/></label><div className="tenant-support-actions"><button type="button" onClick={()=>setCreating(false)}>Cancel</button><button className="tenant-support-primary" disabled={busy}>{busy?"Submitting…":"Submit request"}</button></div></form>}
    <div className="tenant-support-layout"><div className="tenant-support-list"><h3>Your support requests</h3>{tickets.map(ticket=><button key={ticket.id} className={selected===ticket.id?"selected":""} onClick={()=>setSelected(ticket.id)}><span className={"tenant-support-status status-"+ticket.status}>{ticket.status.replaceAll("_"," ")}</span><b>{ticket.subject}</b><small>{ticket.category} · {ticket.priority} priority</small><time>{new Date(ticket.updated_at).toLocaleString()}</time></button>)}{!tickets.length&&<p className="tenant-support-empty">No support requests yet. Use “New support request” to contact our team.</p>}</div>
      <div className="tenant-support-detail">{active?<><div className="tenant-support-ticket-title"><div><small>SUPPORT REQUEST</small><h3>{active.subject}</h3><p>Opened {new Date(active.created_at).toLocaleString()}</p></div><span className={"tenant-support-status status-"+active.status}>{active.status.replaceAll("_"," ")}</span></div><div className="tenant-support-description">{active.description}</div><div className="tenant-support-conversation"><b>Conversation</b>{messages.map(item=><article key={item.id}><small>{item.sender_id===userId?"You / Your company":"EBS PRO Support Team"} · {new Date(item.created_at).toLocaleString()}</small><p>{item.body}</p></article>)}{!messages.length&&<p className="tenant-support-empty">No messages yet. Add a message below if you want to provide more details.</p>}</div><form className="tenant-support-reply" onSubmit={sendReply}><textarea rows={3} value={reply} onChange={event=>setReply(event.target.value)} placeholder="Add information or reply to the support team…"/><button className="tenant-support-primary" disabled={busy||!reply.trim()}>Send message</button></form></>:<div className="tenant-support-empty tenant-support-empty-detail">Select a support request to see its progress and conversation.</div>}</div>
    </div>
    <p className="tenant-support-footnote">Support staff can only access the support case details you submit here. Your company’s financial and operational records remain tenant-isolated.</p>
  </section>;
}
