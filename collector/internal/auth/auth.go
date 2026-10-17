package auth

import (
	"crypto/sha256"
	"crypto/subtle"
)

func Match(want, got string) bool {
	a := sha256.Sum256([]byte(want))
	b := sha256.Sum256([]byte(got))
	return want != "" && subtle.ConstantTimeCompare(a[:], b[:]) == 1
}
