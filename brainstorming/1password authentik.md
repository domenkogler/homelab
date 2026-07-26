Yes, you can integrate your **1Password Family** subscription with **Authentik**, but there is a major constraint regarding *how* you use it. \[1\]

1Password offers an enterprise feature called **Unlock with SSO** (which lets you log into 1Password using Authentik). However, 1Password strictly limits this feature to **Business and Enterprise plans**. It is **not** available on 1Password Families tiers. \[1, 2, 3, 4, 5\]

Even without enterprise SSO, you can still integrate them at a family level using two methods.

## ---

**Method 1: The "Passwordless" Passkey Integration (Highly Recommended)**

You can use Authentik to let your family log into your home lab services without typing a password, utilizing 1Password to securely store and handle the biometric handshake. \[6\]

Instead of typing credentials, they click "Log in with Passkey." **1Password** intercepts the request, prompts them for FaceID/TouchID or their Master Password, and securely logs them into Authentik. \[7, 8, 9, 10, 11\]

## **How to set it up:**

1. In the Authentik Admin interface, go to **Flows and Stages** \> **Stages**.  
2. Ensure you have a **WebAuthn Stage** created (Authentik uses WebAuthn for Passkeys).  
3. Go to **Flows** and bind this WebAuthn stage to your default-authentication-flow.  
4. Have your family members log into Authentik normally, click their profile in the top-right, go to **MFA Devices**, and click **Enroll Passkey/WebAuthn**.  
5. When the browser prompts them to create a passkey, the **1Password Browser Extension** or mobile app will pop up and ask to save it. \[8, 12, 13, 14, 15\]

From then on, logging into Authentik from any device is a one-click biometric experience powered entirely by 1Password. \[16\]

## ---

**Method 2: OIDC Compatibility Mode (For Forms Autofill)**

Because Authentik splits its login screen into two distinct steps (Step 1: Enter Username → Step 2: Enter Password), browser extensions like 1Password can sometimes fail to automatically fill the password box on step 2\. \[17\]

To fix this and ensure 1Password works perfectly for autofilling your family's credentials, you need to enable Authentik's compatibility settings. \[12\]

## **How to set it up:**

1. Log into your **Authentik Admin Interface**.  
2. Navigate to **Flows and Stages** \> **Flows**.  
3. Click on your **default-authentication-flow** (and your default-enrollment-flow if applicable) and click **Edit**.  
4. Check the box for **Compatibility mode**.  
5. Save changes. \[12\]

This forces Authentik to expose standard HTML form fields that the **1Password Extension** looks for, allowing 1Password to natively recognize, prompt, and fill your family's credentials automatically. \[12, 17, 18, 19\]

## ---

**Summary of the ultimate family setup**

Combining your previous goals with 1Password results in a highly optimized workflow:

* **When at Home (LAN / WireGuard)**: Your family goes to Immich, 1Password autofills their username/password (via Compatibility Mode), the conditional IP policy skips 2FA, and they are logged in instantly.  
* **When Remote (Public WAN)**: They log in, Authentik triggers the 2FA stage, and your family can use **1Password Passkeys** or **1Password's built-in Authenticator (TOTP)** to instantly bypass the second factor without opening a separate authenticator app. \[8, 20\]

Would you like assistance setting up the **WebAuthn/Passkey stage** in your Authentik flows to test this out?