# Azure App Registration (one-time setup, ~5 minutes)

1. Go to https://portal.azure.com and sign in with any Microsoft account
2. Search for **App registrations** → **New registration**
3. Fill in:
   - Name: `Invoice Scanner`
   - Supported account types: **Accounts in any organizational directory and personal Microsoft accounts**
   - Redirect URI: Select **Public client/native** → enter `invoicescanner://auth`
4. Click **Register**
5. Copy the **Application (client) ID** — paste it into `AuthManager.swift` where it says `YOUR_CLIENT_ID`
6. Go to **API permissions** → **Add a permission** → **Microsoft Graph** → **Delegated** → add:
   - `Mail.Read`
   - `offline_access` (already included by default)
7. Click **Grant admin consent** (or just leave it — users will consent on first sign-in)

Done. No secrets, no certificates needed — this uses PKCE (public client flow).
