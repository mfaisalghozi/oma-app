# ONB-BE-01 — Supabase Auth readiness

Status: **password policy configured; provider/SMTP/redirect setup and end-to-end verification are pending**.
Source ticket: [ONB-BE-01](https://www.notion.so/40eaab73e0b581d4b39cc9652c59ff3b).
The production dashboard was inspected on 2026-11-05. After confirming the target
and email flow with the user, the ticket-required password policy was set to
minimum 8 characters with **Letters and digits** and verified by reopening the
provider settings. Email confirmation remains enabled. No database migrations,
test users, key rotations, provider enablement, redirects or SMTP changes were applied.

## Confirmed decisions

- Keep the existing **Seoul (`ap-northeast-2`) production project**, per the user's
  confirmation. This supersedes the ticket's Singapore assumption. Approved legal
  documents must describe the actual deployment region.
- Use **email/password with a confirmation link**, per the user's confirmation.
  This supersedes the older backend document's Email OTP wording.
- Supabase Auth handles sign-in. Go validates Supabase JWTs; it does not implement
  Google/Apple callbacks, password verification, or OTP endpoints itself.

## Observed production settings and required changes

| Setting | Observed | Ticket target / next input |
| --- | --- | --- |
| Region | Seoul | Keep, as confirmed by the user |
| Email provider | Enabled | Keep enabled |
| Confirm email | Enabled | Keep enabled |
| Minimum password length | 8 (changed from 6) | Verified |
| Password requirements | Letters and digits (changed from no required characters) | Verified |
| Google provider | Disabled | Configure approved Web/Android/iOS client IDs and provider credential, then enable |
| Apple provider | Disabled | Configure approved application/service IDs and provider credential, then enable |
| Site URL | `http://localhost:3000` | Supply the approved production URL |
| Redirect URL allowlist | Empty | Supply the exact mobile redirect URI for `/auth/callback` and its matching native app configuration |
| Custom SMTP | Disabled | Supply a verified sender domain and SMTP provider configuration |
| JWT signing key | Current ECC P-256 | Compatible with the Go ES256/JWKS validator |
| Older signing key | Previous HS256 | Go rejects HS256; verify refreshed sessions use the current key |

The accompanying `auth-plan.json` is a review record, **not** an importable
Supabase configuration or an automatically applied change.

## Rate limits observed in the dashboard

| Control | Current displayed value |
| --- | --- |
| Auth email sending | 2 emails/hour (built-in sender) |
| Token refresh | 150 requests/5 minutes/IP |
| OTP/magic-link verification | 30 requests/5 minutes/IP |
| Sign-up/sign-in | 30 requests/5 minutes/IP |
| Email minimum interval | 60 seconds/user; dashboard notes this applies with custom SMTP |

No limits were changed. Custom SMTP and its sending capacity must be configured
before verifying production delivery. Review actual limits again after SMTP is
enabled; do not assume the built-in sender is suitable for production.
See [Supabase rate limits](https://supabase.com/docs/guides/auth/rate-limits) and
[custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp).

## Configuration procedure

1. In **Authentication → Sign In / Providers**, retain the verified email policy:
   confirmation enabled, minimum password length 8 and **Letters and digits**.
2. Configure Google using the approved OAuth application credentials. Include the
   appropriate native client IDs and the Web client ID in the supported provider
   configuration. Follow the current
   [Google provider guide](https://supabase.com/docs/guides/auth/social-login/auth-google).
   Do not disable nonce validation merely to work around a client integration issue.
3. Configure Apple using the approved App/Services IDs and developer credentials.
   Follow the [Apple provider guide](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple).
   Record an owner for any provider-secret renewal required by the selected flow.
4. In **Authentication → URL Configuration**, set the agreed production site URL
   and exact mobile redirect URI. A bare `/auth/callback` path is insufficient.
   The provider's redirect back to Supabase and the app's deep link are different
   URLs; configure both according to the
   [redirect guide](https://supabase.com/docs/guides/auth/redirect-urls).
5. In **Authentication → Emails → SMTP Settings**, configure the approved sender,
   verified domain and SMTP credentials. Keep transport/provider credentials in
   Supabase or the approved secret manager, never in the repository or chat.
6. Re-read all saved settings and complete the verification below in an approved
   non-production test environment before considering this ticket complete.

## Three wrong passwords → 15-minute pause

The enforcement boundary is **Supabase Auth**, where password attempts occur.
The Go API receives already-issued JWTs and cannot count failed direct Supabase
password logins. A mobile countdown is UX behavior and cannot enforce a server
lockout against a modified client.

If this exact rule is retained, use an appropriately reviewed Auth-side mechanism,
for example a [password verification hook](https://supabase.com/docs/guides/auth/auth-hooks/password-verification-hook).
Its failed-attempt counters, concurrent attempts, successful-login reset, expiry,
and account-lockout abuse behavior must be tested before attachment. No such hook
has been installed or claimed to enforce the rule in production. This remains a
rollout dependency, rather than a fictitious Go-side lockout.

## Verification still required

- Google and Apple sign-in on the supported Android/iOS flows.
- Email sign-up, confirmation-link delivery and return to the app.
- Rejection of passwords shorter than 8 or missing a letter/digit.
- Confirmation behavior before and after the link is followed.
- A newly issued ES256 session accepted by `POST /v1/me/initialize`.
- Correct app routing through consent, incomplete onboarding and discovery.
- Custom SMTP delivery and agreed rate-limit behavior.
- The exact failed-password pause policy, if retained.

Local account/JWT, API, PostgreSQL/PostGIS and Storage-adapter tests are implemented
in the backend branches. They do not prove live OAuth, SMTP, redirect handling,
Storage policies, or production readiness. Production migrations and test accounts
were not created. No separate staging project was provided.

## Continuation on 2026-11-08

The backend now uses Gin. Supabase still owns password verification and social
sign-in; migrating the HTTP framework does not move Auth into the Go API.

[Public identifiers](public-identifiers.json) records the known project URL,
provider callback URL and native application IDs from the repository. Unknown
production URLs and OAuth client IDs remain `null`. The provider callback back to
Supabase is not the mobile redirect URI. No mobile callback intent filter or iOS
URL scheme is currently configured, and no URI has been invented or allowlisted.

### Read-only public configuration check

Export `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` in your shell or approved
secret manager, then run from the repository root:

```sh
cd apps/api
go run ./cmd/auth-check
```

Use a publishable key (or the legacy anon key), never a service-role or provider
secret. This command does not read `.env` files automatically. It sends one GET
to `/auth/v1/settings`, rejects redirects, limits response size and prints only
named boolean checks. Missing fields fail closed. It creates no users and changes
no settings. Native binary exit codes are 0 when the requested public flags match,
2 when a flag is pending, and 1 for input/network/response errors. `go run` wraps
nonzero program exits, so use a compiled binary if automation needs the exact code.

Checks cover email enabled, confirmation required, signup enabled, Google enabled
and Apple enabled. A matching result does **not** establish correct provider
credentials, the password policy, SMTP delivery, redirect configuration, signing
key rollout or end-to-end sign-in. Disabled Google/Apple flags intentionally keep
the report pending for this ticket.

The response fields follow the official
[Supabase Auth settings implementation](https://github.com/supabase/auth/blob/master/internal/api/settings.go).
HTTP fixture tests cover pending and matching flags, incomplete responses and
redirect protection. The command has not been run against production: no public
key was provided during this continuation, and the prior browser-control tool is
not available in this session. Earlier dashboard observations above are historical,
not a fresh inspection.

A proposed English confirmation email is in
[templates/confirmation.html](templates/confirmation.html). It uses Supabase's
`{{ .ConfirmationURL }}` template variable. Review it under Authentication →
Email Templates before applying it; no production template was changed. See
[Supabase email templates](https://supabase.com/docs/guides/auth/auth-email-templates).

Ticket completion still requires the owning team to provide the public production
Site URL, exact mobile redirect URI, Google client IDs, Apple Services/App IDs and
sender domain, with credentials entered securely into the appropriate dashboards.
Then verify the previously listed flows in an approved non-production environment.
