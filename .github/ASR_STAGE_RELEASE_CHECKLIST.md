# 0.6.73 ASR isolated preview release gate

- Confirm nine public HTTPS sample uploads recognized on the isolated listener.
- Require Xcode 26, an unsigned device build, and four selected native test suites.
- Check `CFBundleShortVersionString=0.6.73`, `CFBundleVersion=133`, `CFBundleIdentifier=dev.together.poc.asrtest`.
- Validate SHA-256 from the artifact root using `sha256sum -c delivery/SHA256SUMS.txt`.
- Publish only the distinct unsigned IPA as a prerelease asset after verification success.
- Keep the original 0.6.72 build and Singapore production routes unchanged.
- User signs the isolated IPA with a matching Apple provisioning profile; staging pairing secret provided out of band.
