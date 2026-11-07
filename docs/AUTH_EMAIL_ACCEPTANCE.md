# EBS PRO real email authentication acceptance

Automated Playwright checks validate the UI and simulate Supabase Auth responses. They deliberately do not send a real signup or password-reset email and do not create a production Auth user.

Use a dedicated test email inbox and a dedicated test company for the real-provider check:

## Signup confirmation

1. Open https://ebs-pro.onrender.com in a private browser session.
2. Choose **Create account** and register with the dedicated test inbox and a strong password.
3. Confirm the app displays the message asking the user to check the inbox.
4. Open the confirmation email and click its confirmation link on the same browser/device.
5. Verify the link returns to the EBS PRO origin, the session is recognized, and the app shows the company setup screen for a new test user.
6. Create only a test company and confirm its owner workspace loads.

## Password recovery

1. Sign out of the test account.
2. On the sign-in page choose **Forgot password?**, enter the test inbox and submit.
3. Open the email and follow its link on the same browser/device.
4. Verify EBS PRO opens the **Set a new password** screen.
5. Set a new strong password, sign in with it, and verify the test company workspace loads.
6. Confirm the old password no longer works.

## Dashboard settings to inspect

In Supabase Dashboard for project vastupafhvlarlllvkao, inspect Authentication > Providers > Email:
- Confirm email setting and the email template/redirect behavior.
- Confirm the Site URL is https://ebs-pro.onrender.com.
- Confirm the redirect allow-list includes the production origin.
- Verify the SMTP configuration and delivery using the test inbox.

The connected Supabase tools cannot read or change these Auth dashboard settings. Do not paste passwords, confirmation links, OTPs, API keys or tokens into chat. The organization is on the Free plan; leaked-password blocking is a Pro+ feature and is intentionally not enabled through a paid upgrade.
