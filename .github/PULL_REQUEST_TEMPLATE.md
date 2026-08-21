## Summary

Describe the user or architecture outcome and why this approach owns it cleanly.

## Verification

List the commands and manual checks actually observed.

- [ ] `dart format --output=none --set-exit-if-changed .`
- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] Relevant desktop build and manual proof
- [ ] No credentials, tokenized URLs, private media data, or unredacted logs

## Platform evidence

Call out unverified platform behavior. Hardware decode, HDR, libmpv, native
presentation, and DirectComposition claims require Windows evidence.
