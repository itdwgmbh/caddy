// Tiny static binary used as Docker HEALTHCHECK. Exits 0 if the admin API
// answers 200 on localhost:2019, otherwise 1.
package main

import (
	"net/http"
	"os"
	"time"
)

func main() {
	c := &http.Client{Timeout: 2 * time.Second}
	resp, err := c.Get("http://localhost:2019/config/")
	if err != nil || resp.StatusCode != http.StatusOK {
		os.Exit(1)
	}
	resp.Body.Close()
}
