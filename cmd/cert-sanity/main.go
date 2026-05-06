// Pre-start sanity sweep for Caddy's certificate storage.
//
// Caddy refuses to load a certificate whose public key doesn't match the
// stored private key ("tls: private key does not match public key") and the
// only recovery is to delete the broken pair so Caddy reissues. This binary
// runs before caddy starts and removes any cert/key/json triple that fails
// the pubkey-equality check.
package main

import (
	"bytes"
	"crypto"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"
	"io/fs"
	"log"
	"os"
	"path/filepath"
	"strings"
)

const defaultRoot = "/data/caddy/certificates"

func main() {
	log.SetFlags(0)
	log.SetPrefix("cert-sanity: ")

	root := defaultRoot
	if v := os.Getenv("CADDY_CERT_ROOT"); v != "" {
		root = v
	}

	if _, err := os.Stat(root); errors.Is(err, fs.ErrNotExist) {
		return
	}

	_ = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".crt") {
			return nil
		}
		base := strings.TrimSuffix(path, ".crt")
		reason := pairProblem(path, base+".key")
		if reason == "" {
			return nil
		}
		log.Printf("removing %s (%s)", base, reason)
		for _, p := range []string{path, base + ".key", base + ".json"} {
			if err := os.Remove(p); err != nil && !errors.Is(err, fs.ErrNotExist) {
				log.Printf("  remove %s: %v", p, err)
			}
		}
		return nil
	})
}

func pairProblem(certPath, keyPath string) string {
	certPub, err := pubFromCert(certPath)
	if err != nil {
		return "cert unreadable: " + err.Error()
	}
	keyPub, err := pubFromKey(keyPath)
	if err != nil {
		return "key unreadable: " + err.Error()
	}
	if !bytes.Equal(certPub, keyPub) {
		return "public key mismatch"
	}
	return ""
}

func pubFromCert(path string) ([]byte, error) {
	der, err := readPEM(path)
	if err != nil {
		return nil, err
	}
	c, err := x509.ParseCertificate(der)
	if err != nil {
		return nil, err
	}
	return x509.MarshalPKIXPublicKey(c.PublicKey)
}

func pubFromKey(path string) ([]byte, error) {
	der, err := readPEM(path)
	if err != nil {
		return nil, err
	}
	for _, parse := range keyParsers {
		k, err := parse(der)
		if err != nil {
			continue
		}
		if signer, ok := k.(crypto.Signer); ok {
			return x509.MarshalPKIXPublicKey(signer.Public())
		}
	}
	return nil, fmt.Errorf("unrecognised private key format")
}

var keyParsers = []func([]byte) (any, error){
	func(b []byte) (any, error) { return x509.ParsePKCS8PrivateKey(b) },
	func(b []byte) (any, error) { return x509.ParseECPrivateKey(b) },
	func(b []byte) (any, error) { return x509.ParsePKCS1PrivateKey(b) },
}

func readPEM(path string) ([]byte, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	block, _ := pem.Decode(raw)
	if block == nil {
		return nil, fmt.Errorf("no PEM block")
	}
	return block.Bytes, nil
}
