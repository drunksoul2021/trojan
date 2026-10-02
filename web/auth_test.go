package web

import (
	"crypto/sha256"
	"fmt"
	"testing"
)

func TestPasswordMatches(t *testing.T) {
	stored := fmt.Sprintf("%x", sha256.Sum224([]byte("correct-password")))
	for _, input := range []string{"correct-password", stored} {
		if !passwordMatches(input, stored) {
			t.Fatal("valid password rejected")
		}
	}
	for _, input := range []string{"wrong-password", ""} {
		if passwordMatches(input, stored) {
			t.Fatal("invalid password accepted")
		}
	}
}
