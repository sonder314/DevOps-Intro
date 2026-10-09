package main

import (
	"fmt"
	"os"
	"time"
)

func main() {
	method := os.Getenv("REQUEST_METHOD")
	path := os.Getenv("PATH_INFO")

	if method != "GET" || path != "/time" {
		fmt.Println("Status: 404 Not Found")
		fmt.Println("Content-Type: application/json")
		fmt.Println()
		fmt.Println(`{"error":"not found"}`)
		return
	}

	now := time.Now().UTC()
	moscow := now.Add(3 * time.Hour)
	iso := moscow.Format("2006-01-02T15:04:05") + "+03:00"
	hourMinute := moscow.Format("15:04")

	fmt.Println("Content-Type: application/json")
	fmt.Println()
	fmt.Printf(
		"{\"unix\":%d,\"iso\":%q,\"hour_minute\":%q,\"timezone\":\"Europe/Moscow (UTC+3)\"}\n",
		now.Unix(),
		iso,
		hourMinute,
	)
}
