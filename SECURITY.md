# Security and responsible handling

This is a private-review source snapshot, not a certified production release.

Do not put secrets, actual user records, session tokens or exploit details in a public issue. Contact the repository owner through the private channel agreed for the review. No response-time guarantee is claimed.

Client configuration is public once embedded in an application. Use only publishable/anon keys there. Service-role credentials, routing-provider credentials, SMS credentials and signing keys belong in private provider/local configuration.

The ignore rules help prevent accidental commits; they do not erase already committed secrets. If a real secret was committed to any previous repository, revoke/rotate it and review Git history. A public client key is not itself proof of a leaked privileged credential; access still depends on server policies.

`npm run check:source` is a limited pattern/syntax check, not a replacement for a dedicated secret scanner, dependency audit or server authorization review. Current known risks are documented in `docs/TECHNICAL-REVIEW.md`.
