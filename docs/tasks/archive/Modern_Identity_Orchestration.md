<!-- SUPERSEDED (2026-05): Stack OIDC compose wiring was removed from this repo. SSO Server as IdP for individual apps remains an operator choice (see docs/hive/GOOGLE_WORKSPACE_OAUTH_NAS_LOGIN.md Path B). Archived under docs/tasks/archive/ for reference only — not an active fleet contract. -->

Modern Identity Orchestration: A Comprehensive Technical Analysis of Synology DiskStation Manager as an OpenID Connect Provider and Client
The paradigm shift in Network Attached Storage (NAS) architecture from localized file repositories to comprehensive application hosting platforms has necessitated a fundamental re-evaluation of identity management. As Synology DiskStation Manager (DSM) evolves, the integration of the OpenID Connect (OIDC) protocol represents a critical infrastructure layer that enables secure, federated identity across a diverse ecosystem of native packages, containerized services, and third-party web applications. This report provides an exhaustive technical analysis of the implementation, governance, and optimization of Synology DSM as both an OIDC Identity Provider (IdP) and a Service Provider (SP), exploring the architectural nuances, security implications, and administrative workflows required for enterprise-grade deployment.
The Architecture of Identity in the Private Cloud
The emergence of OpenID Connect as the dominant standard for modern authentication is rooted in its ability to provide a thin, interoperable identity layer on top of the established OAuth 2.0 authorization framework. While OAuth 2.0 was originally designed to facilitate delegated access—allowing one application to access resources on another without sharing credentials—OIDC extends this by introducing a standardized ID Token. This token, typically formatted as a JSON Web Token (JWT), provides verifiable assertions about the user's identity, thereby enabling a robust Single Sign-On (SSO) experience.[1, 2]
In the context of Synology DSM, this protocol architecture is bifurcated into two primary service packages: the OAuth Service and the SSO Server. Understanding the distinction between these two components is essential for any technical implementation. The OAuth Service acts as an engine for resource authorization, enabling third-party applications to request access tokens that grant permission to interact with Synology Web Services.[3] Conversely, the SSO Server package functions as a comprehensive Identity Provider, supporting OIDC, SAML 2.0, and the proprietary Synology SSO protocol to centralize user authentication across an organization's entire application stack.[4, 5]
Distinguishing Functional Roles within Synology IAM
The following table delineates the primary technical characteristics and use cases for the various identity-related components within the Synology DSM environment.
Component
Protocol Focus
Primary Functional Role
Typical Application
OAuth Service
OAuth 2.0
API-level resource authorization [6]
Scoping access to Synology Photos or File Station APIs [3]
SSO Server
OIDC, SAML, CAS
Identity Provider (IdP) for SSO [4, 5]
Centralizing login for Portainer, Nextcloud, and MailPlus [7]
SSO Client
OIDC, SAML, CAS
Service Provider (SP) integration [8]
Authenticating DSM logins via Microsoft Entra ID or Authelia [9, 10]
Secure SignIn
FIDO2, TOTP, MFA
Secondary authentication layer [5, 6]
Enforcing hardware-based security for IdP logins [7]
The architectural choice to separate these packages allows for granular control over how identity and authorization data is exposed. For instance, an organization may deploy the OAuth Service to allow a third-party mobile app to upload files to a NAS via an access token, while simultaneously utilizing the SSO Server to ensure that the user logs into that app using their corporate credentials via an OIDC ID Token.[1, 6, 11]
Infrastructure Prerequisites and Network Hardening
The deployment of a functional OIDC provider on a Synology NAS is predicated on a stable and secure network foundation. Because OIDC relies on browser-side redirects and backend token exchanges, the resolution of hostnames and the integrity of TLS certificates are paramount.
Domain Resolution and Dynamic DNS Implementation
The OIDC protocol strictly requires that the Identity Provider be accessible via a resolvable domain name rather than an IP address. Synology DSM facilitates this through its integrated Dynamic Domain Name System (DDNS) settings. Within the Control Panel, under External Access, administrators can map a unique hostname—such as identity.synology.me—to the NAS's public IP address.[12, 13] This hostname serves as the foundational "Server URL" for all OIDC discovery documents and redirect URIs.[14]
A critical technical constraint in the Synology OIDC implementation is the explicit exclusion of QuickConnect addresses and raw IP addresses for authentication redirects.[15, 16] This limitation is enforced to maintain compatibility with modern browser security policies, which often reject cross-origin requests that do not originate from a valid, HTTPS-secured domain name. Furthermore, the DDNS service supports a "Heartbeat" mechanism, which ensures that administrators receive immediate notification if the mapping between the hostname and the IP address fails, thereby preventing unexpected downtime in the identity infrastructure.[12, 17]
Security Layers and Encryption Standards
Encryption is not merely an optional enhancement for OIDC; it is a fundamental protocol requirement. The transmission of sensitive authorization codes and identity tokens must occur over HTTPS to prevent interception by malicious actors. Synology simplifies the procurement of valid TLS certificates by integrating with the Let's Encrypt Certificate Authority.[12, 17] When configuring a Synology DDNS hostname, the system prompts the administrator to obtain a certificate and set it as the default for DSM services, ensuring that all OIDC endpoints—such as the authorization and token endpoints—are backed by a trusted certificate.[17, 18]
Security Parameter
Requirement
Impact of Non-Compliance
Protocol
HTTPS (Port 443)
Tokens and user credentials sent in plaintext; vulnerable to interception [4]
Certificate
Trusted CA-Signed
Browser security warnings; modern OIDC clients will reject the login flow [4]
iFrame Policy
Allowed Websites List
SSO login windows will be blocked if "Do not allow DSM to be embedded with iFrame" is active [5, 7]
TLS Version
TLS 1.2 or 1.3
Older versions are susceptible to known cryptographic attacks; potentially breaks client compatibility [18]
Furthermore, the "Application Portal" settings in DSM allow for the customization of ports and domains for specific services. For an SSO Server deployment, it is highly recommended to utilize the default HTTPS port (443) or a dedicated alias to ensure that the identity service is not obscured by non-standard port requirements, which can occasionally complicate the configuration of third-party OIDC clients.[18]
Implementing the Synology SSO Server as an OIDC Provider
The transformation of Synology DSM into a centralized identity hub begins with the configuration of the SSO Server package. This process involves setting the global identity parameters and then registering individual applications that will delegate their authentication to the NAS.
Fleet OIDC operator checklist (PSU, Open WebUI, Portainer, and similar OIDC clients)

**Archive location:** **`docs/tasks/archive/Modern_Identity_Orchestration.md`** (superseded; see HTML comment at top of this file).

Required scopes for typical DSM-backed integrations: **`openid profile email groups`** — omit or narrow **`groups`** only when the client explicitly does not need DSM group claims.

Username mapping: prefer the **`preferred_username`** claim when the Identity Provider issues it and the downstream application supports it; otherwise use **`sub`** as the stable subject identifier for account correlation.

Redirect URIs must match registered values strictly (scheme, host, port, path, and trailing slash discipline); otherwise deployments commonly fail with **`redirect_uri_mismatch`**.

Synology SSO Server **Account Type** must remain **`Domain/LDAP/local`** when local NAS accounts or DSM-aligned directory users must interoperate with OIDC tokens issued for containerized services.

Related repo tooling scope (Apple / Synology extended-attribute clutter): Upstream **`hwdbk/synology-scripts`** **`cleanup_SynoFiles`** can remove “bogus” **`@SynoEAStream`**/**`@SynoResource`** metadata using compiled **`get_attr`** plus an **`xattrs.lst`** policy file. **This repository intentionally does not implement that helper-dependent bogus-xattr path.** The maintained script **`scripts/maintenance/remove_apple_hidden_files.sh`** stays limited to safe, operator-reviewed patterns: paired/small **`._*`** stubs (optional orphan mode), **`.DS_Store`** / **`.AppleDouble`**, and **opt-in** removal of **stray** **`@SynoEAStream`**/**`@SynoResource`** files only when the primary file path no longer exists — see script header comments for toggles.

Global Configuration and Discovery Metadata
The initial setup occurs in the General Settings tab of the SSO Server. The administrator must first define the "Account Type," which dictates the source of user identities for the SSO service. The "Domain/LDAP/local" option is the most versatile, as it allows for a hybrid environment where local NAS users, as well as users from a connected Active Directory or LDAP directory, can all utilize the same SSO infrastructure.[14, 19]
Following the account type selection, the "Server URL" must be defined. This URL is the cornerstone of the OIDC discovery process. Once the OIDC service is enabled in the Service tab, the NAS generates a "Well-known URL"—typically https://[your-domain]/.well-known/openid-configuration.[4] This endpoint provides a JSON document that OIDC-compliant applications use to automatically discover the NAS's supported scopes, claims, and cryptographic signing keys.[4, 15, 19] Copying this URL and providing it to client applications is the most effective way to ensure a seamless integration, as it eliminates the need to manually enter individual endpoint URLs.[15, 19]
Application Registration and Client Credentials
For every application that will trust the Synology NAS for authentication, a unique application profile must be created within the SSO Server's Application tab. This registration process establishes the trust relationship between the IdP and the SP.
Application Name: This is the display name that may appear on the SSO login portal.[15]
Redirect URI: This is the most critical configuration point. It is the specific URL within the client application where the SSO Server will send the user and the authorization code after a successful login.[15, 19] Synology supports the registration of up to 10 redirect URIs per application profile, which is vital for organizations that maintain multiple environments, such as development, staging, and production.[15, 16]
Client Identification: Upon completing the registration, the system generates an "Application ID" (Client ID) and an "Application Secret" (Client Secret). These act as the credentials that the client application uses to identify itself to the SSO Server during the token exchange phase of the OIDC flow.[15, 19]
Deep Dive into the JSON Web Token (JWT) Structure
The effectiveness of OIDC as an identity protocol is derived from its use of JSON Web Tokens. These tokens are compact, URL-safe means of representing claims to be transferred between two parties. When a user authenticates via the Synology SSO Server, the server issues an ID Token that contains standardized and custom claims that describe the user and the authentication event.[4, 20]
Analysis of Synology OIDC Claims
A JWT issued by the Synology SSO Server typically follows the standard format of a Header, a Payload, and a Signature. The Payload section contains the assertions (claims) that the client application uses to verify the user's identity.
Claim
Technical Description
Implication for Application Integration
iss
Issuer: The URL of the SSO Server
Applications must verify this against their configured issuer to prevent "token injection" attacks [4, 20]
sub
Subject: The unique identifier for the user
Often formatted as username or username@domain. This is the primary key for user mapping [4]
aud
Audience: The Application ID of the client
Ensures that the token was intended specifically for the application receiving it [4]
email
The user's registered email address
Essential for applications that use email as a primary identifier, such as Nextcloud [4]
groups
A JSON array of the user's group memberships
Critical for implementing group-based access control (RBAC) in the client app [4]
username
The raw username of the user
Provides a human-readable identifier that matches the Synology login [4, 20]
exp
Expiration: The time after which the token is invalid
Prevents the use of intercepted tokens after a certain period; managed via common settings [3, 4]
The inclusion of the groups claim is a significant feature of the Synology implementation, as it allows for the synchronization of organizational structures between the NAS and integrated services. For example, a user belonging to the "Administrators" group on the NAS can be automatically granted administrative privileges in a containerized application like Portainer by configuring the application to look for that specific string within the groups claim array.[4, 21]
Understanding Scopes and Data Disclosure
Scopes are the mechanism by which a client application requests specific sets of information from the Identity Provider. When configuring an application to use Synology OIDC, administrators must specify the scopes required for the integration to function correctly.
openid: This is the mandatory scope that signals the request is for OIDC authentication.[22]
profile: This scope requests access to basic user profile information, which may include the username and full name.[9, 23]
email: This scope is required if the application needs to retrieve the user's email address for account mapping or communication.[22]
groups: This scope is necessary for the ID Token to include the array of group memberships.[22, 23]
If an administrator fails to include the groups scope in the client application's configuration, the resulting ID Token will omit the group data, even if the user is a member of multiple groups on the NAS.[22, 23] This often leads to authorization failures where the user can log in but lacks the necessary permissions within the application.
Governance and Access Control in the OIDC Ecosystem
Deploying an OIDC provider requires a clear strategy for managing who can access which applications. Synology DSM provides several layers of administrative control to govern the identity lifecycle.
Application Privileges and User-Specific Access
The SSO Server package does not operate in a vacuum; it is deeply integrated with the standard DSM "Application Privileges" system. Even if an application is registered in the SSO Server, a user will only be able to authenticate if they have been granted the privilege to use the "SSO Server" application within the DSM Control Panel.[24, 25]
Administrators can manage these permissions at either the user or group level. The privilege model in DSM follows a "Deny > Allow" hierarchy. If a user is a member of a group that is explicitly denied access to the SSO Server, that denial will override any individual allow permissions granted to that user.[24, 25, 26] This granular control allows administrators to restrict SSO usage to specific departments or security tiers. Additionally, the "Default Privileges" setting can be used to either grant SSO access to all users by default or require an opt-in approach where access must be manually granted to each new account.[24, 26, 27]
Token Management and Session Governance
The governance of identity tokens is essential for maintaining a secure environment. In the OAuth Service interface, administrators can manage "Authorized Items," providing a real-time view of which third-party applications have active authorizations from NAS users.[3, 28] If a security breach is suspected, or if an application is no longer in use, administrators can globally revoke authorizations, effectively terminating all active sessions for that specific application.[3, 28]
Furthermore, the "Common Settings" section allows for the configuration of default token expiration times. Balancing user convenience with security is a critical task for the administrator; while longer expiration times reduce the frequency of login prompts, they also increase the window of opportunity for an attacker to use a compromised token.[3, 28] The system allows these settings to be applied to all new tokens issued by the service.[3]
Case Study: Integration with Containerized and Web Applications
The practical value of a Synology OIDC provider is most evident when integrating with popular self-hosted services. Two prominent examples are Portainer for container management and Nextcloud for collaboration.
Portainer: Mapping OIDC Identity to Container Orchestration
Portainer is a powerful management interface for Docker environments, often deployed on Synology NAS using the Container Manager package.[29] By integrating Portainer with Synology SSO, administrators can eliminate the need for separate Portainer accounts.
The implementation requires creating an OIDC application profile in the Synology SSO Server, using the Portainer instance's URL—for example, https://your-nas.synology.me/portainer/—as the Redirect URI.[21] Within the Portainer settings, under Authentication, OIDC is selected as the primary source. The administrator then enters the Application ID and Secret generated by the NAS. A sophisticated feature of this integration is "Automatic Team Membership." By specifying groups as the claim name, Portainer can automatically map Synology user groups to Portainer Teams.[21] This ensures that when a developer logs in via OIDC, they are immediately granted access to the Docker stacks and volumes associated with their department without any manual intervention by the Portainer administrator.[21]
Nextcloud: Federated Identity and Attribute Mapping
Nextcloud is a comprehensive productivity suite that supports OIDC through the user_oidc application.[30, 31] Integrating Nextcloud with a Synology OIDC provider allows for a seamless transition from the NAS's file services to Nextcloud's collaborative environment.
A common technical challenge in this integration is the mapping of the "Username Claim." While Synology often uses sub or username, Nextcloud may expect a claim such as preferred_username or email.[8, 9, 32] If the mapping is incorrect, Nextcloud may create a new, empty user profile rather than linking the OIDC login to an existing account. Furthermore, the user_oidc app can be configured for "Bearer token validation," allowing other services to use the tokens issued by the Synology NAS to interact with the Nextcloud API on behalf of the user.[31] For larger deployments, the "OIDC Groups Mapping" app can be added to Nextcloud, providing a rule-based engine to translate the complex JSON array of Synology groups into specific Nextcloud roles and quotas.[33, 34]
DSM as an OIDC Client: External Identity Providers
In addition to acting as a provider, Synology DSM can function as an OIDC client, allowing users to log into the NAS using credentials from an external Identity Provider. This is frequently used to integrate Synology hardware into corporate environments using Microsoft Entra ID or to utilize advanced open-source IAM solutions like Authelia and Authentik.[9, 10, 22]
Configuration Logic for External IdPs
To set DSM as an OIDC client, the administrator navigates to the Domain/LDAP section of the Control Panel. Enabling the "OpenID Connect SSO service" opens a configuration window that mirrors the requirements of the SSO Server.
Well-known URL: This is the discovery endpoint of the external IdP (e.g., https://auth.example.com/.well-known/openid-configuration).[8, 23]
Application ID and Secret: These are the credentials provided by the external IdP after registering the Synology NAS as a client application.[8, 9, 22]
Redirect URI: This is the URL of the Synology NAS itself. It must match the URI registered on the external IdP exactly.[8, 9, 35]
Account Type: To allow local NAS users to log in via the external IdP, this must be set to "Domain/LDAP/local".[8]
The Just-In-Time (JIT) Provisioning Gap
A significant architectural limitation in Synology's OIDC client implementation is the lack of automatic user provisioning. Unlike many enterprise SaaS applications that create a new user account upon a successful OIDC login, Synology DSM requires that a user with a matching username already exist in the NAS's database.[22, 32]
If a user authenticates via Authelia, but their username (jdoe) does not exist on the Synology NAS, the login will fail with a privilege error.[32] To resolve this, administrators typically synchronize both the external IdP and the Synology NAS with the same backend directory service (such as LDAP or Active Directory). This ensures that the sub or username claim provided by the IdP always correlates with a valid account on the NAS.[8, 22] In instances where a directory service is not used, the administrator must manually create local user accounts that match the identifiers used by the external IdP.[32]
Advanced Troubleshooting and Failure Analysis
The complexity of the OIDC handshake—involving multiple redirects, cryptographic signatures, and backend communication—means that even minor configuration errors can result in authentication failures.
Diagnosing Redirect URI Mismatches
The "Redirect URI Mismatch" is the most frequent error encountered during OIDC deployment. The protocol mandates an exact, character-for-character match between the URI registered in the IdP and the URI sent by the client application during the authorization request.[36, 37]
The following table summarizes common causes of redirect mismatches and their technical resolutions.
Error Source
Technical Cause
Resolution Strategy
Protocol
http vs. https mismatch
Ensure both the application and the SSO Server registration use the same protocol; HTTPS is mandatory for production [36, 37, 38]
Trailing Slash
/callback vs. /callback/
Standardize the use of trailing slashes; modern OIDC servers treat these as distinct paths [36, 38, 39]
Port Mapping
Missing or incorrect port numbers
If the application is running on a non-standard port (e.g., 9443), that port must be explicitly included in the registered URI [36, 37]
Proxy Rewriting
Reverse proxy altering the path
Inspect the X-Forwarded-Proto and X-Forwarded-Host headers to ensure the original request information reaches the SSO Server [37]
Hostname
IP address vs. FQDN
OIDC requires an FQDN; replace any IP-based redirect URIs with the registered DDNS or custom domain [15]
When troubleshooting, administrators should examine the URL of the failed login attempt. The redirect_uri parameter in the browser's address bar will show exactly what the application is requesting. This value should be copied directly and pasted into the application profile in the Synology SSO Server to ensure a perfect match.[37, 39]
Claim Mapping and Identifier Conflicts
A successful OIDC flow may still end in an error if the Identity Provider and the Service Provider cannot agree on a user's identifier. If the Synology SSO Server sends the user's ID in the sub claim, but the client application is configured to look for the user's ID in the preferred_username claim, the application will receive a null value for the user identity.[8, 32]
In environments utilizing multiple Synology NAS units (one as IdP and others as clients), the system explicitly recommends using the sub claim as the primary username claim to maintain identity consistency across the cluster.[4, 20] In more complex scenarios, such as integrating with Microsoft Entra ID, the claim mapping may need to be adjusted to upn (User Principal Name) or email depending on how the Synology NAS was joined to the domain.[10]
Security Hardening and Future Outlook
As the centralization of identity increases the impact of a single compromised account, security hardening of the Synology OIDC infrastructure is a critical responsibility.
Multi-Factor Authentication and FIDO2 Integration
Synology's "Secure SignIn" framework provides an essential defense-in-depth layer for OIDC. When a user logs into the SSO Server portal, the system can enforce the use of FIDO2-compliant hardware security keys, such as Yubikeys, or biometric approval via the Secure SignIn mobile app.[5, 6] Because this authentication happens at the IdP level, it effectively protects all OIDC-integrated applications, regardless of whether those applications natively support MFA.[6, 7]
Furthermore, the SSO Server allows for the configuration of 2-factor authentication at the account level. Once enabled, users will be prompted for their secondary factor during every SSO login attempt, thereby mitigating the risks associated with password theft or credential stuffing attacks.[7]
Monitoring and Event Logging
The SSO Server provides comprehensive logging of all authentication events and configuration changes. Administrators should regularly review these logs to identify suspicious patterns, such as repeated failed login attempts from unknown IP addresses or unauthorized changes to application redirect URIs.[5, 40] These logs can also be used to verify that the system is properly handling the rotation of cryptographic keys and that tokens are expiring as expected according to the configured policies.[5]
Convergence of Protocols: OIDC as the Successor to SAML
While Synology continues to support SAML 2.0 and CAS for enterprise legacy integration, the industry trend is clearly toward OIDC. The lightweight JSON-based nature of OIDC makes it more suitable for modern web and mobile applications compared to the XML-heavy SAML protocol.[1, 11] As Synology DSM continues to evolve, we can expect further refinements to its OIDC implementation, potentially including support for more complex claims, better integration with cloud-native directory services, and perhaps the eventual inclusion of automatic user provisioning.
The integration of OIDC into Synology DSM transforms the NAS from a simple storage device into a sophisticated identity orchestrator for the private cloud. By mastering the nuances of application registration, claim mapping, and redirect URI management, administrators can build a secure, efficient, and user-friendly identity ecosystem that scales with the needs of their organization. Whether managing a small team or a distributed enterprise, the deployment of Synology as an OIDC provider represents a significant step forward in the modernization of local IT infrastructure.
--------------------------------------------------------------------------------
Single Sign-On(SSO): SAML vs OAuth vs OIDC - What's the Difference | Commandline Ninja, https://commandline.ninja/saml-oauth-oidc/
SSO vs SAML vs OAuth vs OIDC: Understanding Modern Authentication & Authorization, https://dev.to/neelendra_tomar_27/sso-vs-saml-vs-oauth-vs-oidc-understanding-modern-authentication-authorization-1man
OAuth Service - Knowledge Center - Synology, https://kb.synology.com/en-global/DSM/help/OAuthService/oauth_service_desc?version=7
Service | SSO Server - Knowledge Center - Synology, https://kb.synology.com/en-global/DSM/help/SSOServer/sso_server_service?version=7
SSO Server Technical Specifications | Synology Inc., https://www.synology.com/en-eu/dsm/7.2/software_spec/sso_server
OAuth Service Technical Specifications | Synology Inc., https://www.synology.com/en-us/dsm/7.3/software_spec/oauth
SSO Server - Synology Knowledge Center, https://www.synology.com/knowledgebase/DSM/help/SSOServer/sso_server_desc
SSO Client | DSM - Knowledge Center - Synology, https://kb.synology.com/en-global/DSM/help/DSM/AdminCenter/file_directory_service_sso?version=7
Integrate with Synology DSM (DiskStation Manager) | authentik, https://integrations.goauthentik.io/infrastructure/synology-dsm/
Microsoft Entra SSO Service | DSM - Knowledge Center - Synology, https://kb.synology.com/en-global/DSM/help/DSM/AdminCenter/file_directory_service_sso_Azure?version=7
SSO vs OAuth: Key Differences You Must Know - WorkOS, https://workos.com/blog/sso-vs-oauth
DDNS | DSM - Knowledge Center - Synology, https://kb.synology.com/en-global/DSM/help/DSM/AdminCenter/connection_ddns?version=7
DDNS | DSM - Knowledge Center - Synology, https://kb.synology.com/en-global/DSM/help/DSM/AdminCenter/connection_ddns?version=6
General Settings | SSO Server - Knowledge Center - Synology, https://kb.synology.com/en-ph/DSM/help/SSOServer/sso_server_general_setting?version=7
Application | SSO Server - Knowledge Center - Synology, https://kb.synology.com/en-global/DSM/help/SSOServer/sso_server_application_list?version=7
Application | SSO Server - Synology Bilgi Merkezi, https://kb.synology.com/tr-tr/DSM/help/SSOServer/sso_server_application_list?version=7
DDNS | DSM - Synology Bilgi Merkezi, https://kb.synology.com/tr-tr/DSM/help/DSM/AdminCenter/connection_ddns?version=6
Application Portal | DSM - Synology Knowledge Center, https://www.synology.com/knowledgebase/DSM/help/DSM/AdminCenter/application_appportalias
How do I use Synology SSO Server to set up OIDC SSO for DSM? - Knowledge Center, https://kb.synology.com/en-af/DSM/tutorial/set_up_oidc_for_dsm_in_sso_server
Service | SSO Server - Synology Kunskapscenter, https://kb.synology.com/sv-se/DSM/help/SSOServer/sso_server_service?version=7
Portainer on Synology: One Login to Rule Them All | by Tom | perspikapps | Medium, https://medium.com/perspikapps/portainer-on-synology-one-login-to-rule-them-all-74b658994e6d
Synology DSM | OpenID Connect 1.0 | Integration - Authelia, https://www.authelia.com/integration/openid-connect/clients/synology-dsm/
Synology DSM (and apps) with Authelia #4160 - GitHub, https://github.com/authelia/authelia/discussions/4160
Privileges | DSM - Knowledge Center - Synology, https://kb.synology.com/en-global/DSM/help/DSM/AdminCenter/application_appprivilege?version=6
Privileges | DSM - Knowledge Center - Synology, https://kb.synology.com/en-uk/DSM/help/DSM/AdminCenter/application_appprivilege?version=6
Application Privileges | DSM - Knowledge Center - Synology, https://kb.synology.com/en-au/DSM/help/DSM/AdminCenter/application_appprivilege?version=7
Application Privileges | DSM - Knowledge Center - Synology, https://kb.synology.com/en-global/DSM/help/DSM/AdminCenter/application_appprivilege?version=7
OAuth Service - Synology Kunskapscenter, https://kb.synology.com/sv-se/DSM/help/OAuthService/oauth_service_desc?version=7
How to Install Portainer on Synology NAS (DSM 7) - OneUptime, https://oneuptime.com/blog/post/2026-03-20-portainer-synology-nas-dsm7/view
How to install Nextcloud on a Synology NAS - Ionos, https://www.ionos.co.uk/digitalguide/server/configuration/nextcloud-synology/
User authentication with OpenID Connect - Nextcloud Documentation, https://docs.nextcloud.com/server/stable/admin_manual/configuration_user/user_auth_oidc.html
Setting up Synology DSM OpenID with an existing user? : r/Authentik - Reddit, https://www.reddit.com/r/Authentik/comments/1i4h3ws/setting_up_synology_dsm_openid_with_an_existing/
PSA: Update your Nextcloud property mappings (for Authentik OIDC users) - Reddit, https://www.reddit.com/r/NextCloud/comments/1rx0ctg/psa_update_your_nextcloud_property_mappings_for/
Introducing OIDC Groups Mapping — map multiple OIDC claims to Nextcloud groups, https://help.nextcloud.com/t/introducing-oidc-groups-mapping-map-multiple-oidc-claims-to-nextcloud-groups/242145
SSO Client | DSM - Synology Kunskapscenter, https://kb.synology.com/sv-se/DSM/help/DSM/AdminCenter/file_directory_service_sso?version=7
Fixing OAuth 2.0 Redirect URI Mismatches - Reform.app, https://www.reform.app/blog/fixing-oauth-2-0-redirect-uri-mismatches
Authorization Code Flow & redirect_uri_mismatch Errors: Monitoring & Fixing, https://www.dotcom-monitor.com/blog/auth-code-flow-redirect-uri-mismatch-monitoring/
How to Fix 'Invalid Redirect URI' OAuth2 Errors - OneUptime, https://oneuptime.com/blog/post/2026-01-24-fix-invalid-redirect-uri-oauth2/view
How the fix redirect_uri_mismatch error. #googledevelopers #googleoauth - YouTube, https://www.youtube.com/watch?v=QHz1Rs6lZHQ
Synology NAS User's Guide for DSM 7.2, https://kb.synology.com/en-af/UG/Syno_UsersGuide_NAServer_7_2/3