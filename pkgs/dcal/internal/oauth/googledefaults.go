package oauth

import "encoding/base64"

// Shipped OAuth client for official builds (Google "Desktop app" client type,
// public per the installed-app model). Encoded — not encrypted — only so the
// values are not searchable plaintext in the repository; installed-app
// credentials cannot be kept confidential.
//
// These credentials identify the upstream dcal application.
// Distribution packages built from this repository may ship them unchanged;
// forks, rebranded builds, and unrelated applications are not authorized to
// use them (see "OAuth client credentials" in the README) and must register
// their own client, overriding both vars via
// -ldflags "-X .../internal/oauth.builtinGoogleClientID=..." (plaintext), or
// blanking the encoded vars to require user-supplied credentials.
var (
	builtinGoogleClientID     = ""
	builtinGoogleClientSecret = ""
	encodedGoogleClientID     = "VVZCHFlVV1VAQFVfAwJSBQYCVgZfVQQLDBsTEV8YCwcHHQ9XFB5cAlENBUARSE8UExJCAwoZSQEAFhIRBgIJQBAGDxhKBhlD"
	encodedGoogleClientSecret = "Iyo1fT09TgYmAyI/TzVTORZTFEV+NB0pFAUHGRdkLgUFDxY="
)

func BuiltinGoogleCredentials() (GoogleAppCredentials, bool) {
	switch {
	case builtinGoogleClientID != "" && builtinGoogleClientSecret != "":
		return GoogleAppCredentials{ClientID: builtinGoogleClientID, ClientSecret: builtinGoogleClientSecret}, true
	case builtinGoogleClientID != "" || builtinGoogleClientSecret != "":
		return GoogleAppCredentials{}, false
	}

	id := deobfuscate(encodedGoogleClientID)
	secret := deobfuscate(encodedGoogleClientSecret)
	if id == "" || secret == "" {
		return GoogleAppCredentials{}, false
	}
	return GoogleAppCredentials{ClientID: id, ClientSecret: secret}, true
}

func deobfuscate(encoded string) string {
	raw, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		return ""
	}
	key := "dev.mecattaf.dcal"
	for i := range raw {
		raw[i] ^= key[i%len(key)]
	}
	return string(raw)
}
