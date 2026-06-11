package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/nats-io/nats.go"
)

const (
	flushBatch = 250
)

func main() {
	var (
		url      = flag.String("url", "nats://e:x@127.0.0.1:4232", "NATS server URL")
		count    = flag.Int("count", 1000, "number of unique subscriptions to create")
		prefix   = flag.String("prefix", "edge.device", "subject prefix")
		duration = flag.Duration("duration", 0, "hold duration after subscriptions are created; 0 waits until interrupted")
	)
	flag.Parse()

	if *count <= 0 {
		fmt.Fprintln(os.Stderr, "count must be greater than zero")
		os.Exit(2)
	}

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	nc, err := nats.Connect(*url, nats.Name("subscription-load"))
	if err != nil {
		fmt.Fprintf(os.Stderr, "connect failed: %v\n", err)
		os.Exit(1)
	}
	defer nc.Close()

	var created atomic.Int64
	start := time.Now()
	for i := 1; i <= *count; i++ {
		subject := fmt.Sprintf("%s.%06d.status", *prefix, i)
		if _, err := nc.Subscribe(subject, func(*nats.Msg) {}); err != nil {
			fmt.Fprintf(os.Stderr, "subscribe %s failed: %v\n", subject, err)
			os.Exit(1)
		}
		created.Add(1)

		if i%flushBatch == 0 || i == *count {
			if err := nc.Flush(); err != nil {
				fmt.Fprintf(os.Stderr, "flush failed after %d subscriptions: %v\n", i, err)
				os.Exit(1)
			}
			fmt.Printf("created %d/%d subscriptions\n", i, *count)
		}

		select {
		case <-ctx.Done():
			fmt.Printf("interrupted after creating %d subscriptions\n", created.Load())
			return
		default:
		}
	}

	fmt.Printf("ready: %d subscriptions on %s.* via %s in %s\n", created.Load(), *prefix, *url, time.Since(start).Round(time.Millisecond))
	if *duration > 0 {
		select {
		case <-ctx.Done():
		case <-time.After(*duration):
		}
		return
	}
	<-ctx.Done()
}
