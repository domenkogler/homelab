**Yes, you can absolutely use OpenCloud with Authentik OIDC on your VPS.** In fact, OpenCloud natively relies entirely on OpenID Connect (OIDC) for its user authentication and identity management. \[1, 2, 3\]

When configuring this setup alongside your OpenCloud AppImage desktop client, keep the following configuration blueprint in mind to ensure everything connects seamlessly:

## **1\. Configure the OpenCloud Server Environment**

You will need to pass several OIDC variables to your OpenCloud deployment (typically inside your docker-compose environment or .env file): \[1, 4, 5, 6, 7\]

*`# Point to your Authentik application flow`*  
`OC_OIDC_ISSUER=https://yourdomain.com`

*`# Turn off OpenCloud's built-in Identity Provider to save resources`*  
`OC_EXCLUDE_RUN_SERVICES=idp`

*`# Forward the well-known OIDC configuration endpoint through OpenCloud`*  
`PROXY_OIDC_REWRITE_WELLKNOWN="true"`  
`PROXY_OIDC_ACCESS_TOKEN_VERIFY_METHOD="jwt"`

*`# Map Authentik usernames to OpenCloud attributes`*  
`PROXY_USER_OIDC_CLAIM=preferred_username`  
`PROXY_USER_CS3_CLAIM=username`

## **2\. The Multi-Client Trick in Authentik**

A common point of confusion when setting up Authentik with OpenCloud involves the native desktop and mobile clients. OpenCloud's Web UI, Desktop client (AppImage), and mobile apps each require distinct OAuth flows: \[1, 2, 8, 9\]

> * **Option A (The Unified Approach):** In recent OpenCloud updates, you can use a unified provider. You configure a single Authentik OIDC provider (e.g., Client ID: opencloud), but ensure you add multiple **Redirect URIs** to that single provider to match the desktop and web callback endpoints. \[1, 10\]  
> * **Option B (Dedicated Providers):** Create separate application/provider pairs in Authentik for your Web UI and your Desktop client using the official Authentik ownCloud/OpenCloud integration matrix. \[1, 8\]

## **3\. Adjust Content Security Policies (CSP)**

Because the AppImage desktop client and web interface will redirect through your Authentik login portal, you must tell OpenCloud to trust the Authentik domain. \[10\]

> * Locate your OpenCloud csp.yaml file on the VPS.  
> * Add your Authentik domain (https://yourdomain.com) under both connect-src and frame-src. If you skip this, your browser and client may block the Authentik login prompt due to strict browser security policies. \[10, 11\]

Would you like a sample **Authentik Provider configuration block** detailing the exact Redirect URIs required for the desktop AppImage, or do you need help debugging a **401/Client ID error** you are currently seeing?

\[1\] [https://integrations.goauthentik.io](https://integrations.goauthentik.io/chat-communication-collaboration/opencloud/)  
\[2\] [https://github.com](https://github.com/opencloud-eu/ios/issues/4)  
\[3\] [https://github.com](https://github.com/opencloud-eu/android/issues/111)  
\[4\] [https://opencloud.eu](https://opencloud.eu/en/install-opencloud-simply-your-own-server)  
\[5\] [https://help.perforce.com](https://help.perforce.com/helix-core/integrations-plugins/helix-auth-svc/current/Content/HAS/example-configs.html)  
\[6\] [https://www.reddit.com](https://www.reddit.com/r/netbird/comments/1ryu04x/disable_embedded_idp_dex_and_use_external_oidc/)  
\[7\] [https://www.reddit.com](https://www.reddit.com/r/Authentik/comments/1b6iyfe/cant_protect_feishin_nor_homarr_via_npm/)  
\[8\] [https://integrations.goauthentik.io](https://integrations.goauthentik.io/chat-communication-collaboration/owncloud/)  
\[9\] [https://connect2id.com](https://connect2id.com/products/server/docs/archive/v5/guides/login-page)  
\[10\] [https://github.com](https://github.com/orgs/opencloud-eu/discussions/1014)  
\[11\] [https://github.com](https://github.com/orgs/opencloud-eu/discussions/835)