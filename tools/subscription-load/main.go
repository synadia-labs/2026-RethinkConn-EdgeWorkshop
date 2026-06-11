package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/nats-io/jsm.go/natscontext"
	"github.com/nats-io/nats.go"
)

const (
	flushBatch = 250
)

func main() {
	var (
		node      = flag.String("node", "l1", "NATS CLI context or workshop node name to connect to")
		serverURL = flag.String("url", "", "explicit NATS server URL; overrides --node")
		count     = flag.Int("count", 1000, "number of unique subscriptions to create")
		prefix    = flag.String("prefix", "edge.device", "subject prefix")
		duration  = flag.Duration("duration", 0, "hold duration after subscriptions are created; 0 waits until interrupted")
	)
	flag.Parse()

	if *count <= 0 {
		fmt.Fprintln(os.Stderr, "count must be greater than zero")
		os.Exit(2)
	}

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	target, err := resolveConnectTarget(*node, *serverURL)
	if err != nil {
		fmt.Fprintf(os.Stderr, "resolve target failed: %v\n", err)
		os.Exit(2)
	}

	opts := make([]nats.Option, 0, len(target.options)+2)
	opts = append(opts, target.options...)
	opts = append(opts, nats.Name("subscription-load"), nats.NoReconnect())
	nc, err := nats.Connect(target.url, opts...)
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

	fmt.Printf("ready: %d subscriptions on %s.* via %s in %s\n", created.Load(), *prefix, target.description(), time.Since(start).Round(time.Millisecond))
	if *duration > 0 {
		select {
		case <-ctx.Done():
		case <-time.After(*duration):
		}
		return
	}
	<-ctx.Done()
}

type connectTarget struct {
	name    string
	url     string
	options []nats.Option
}

func (target connectTarget) description() string {
	return fmt.Sprintf("%s (%s)", target.name, target.url)
}

func resolveConnectTarget(node, explicitURL string) (connectTarget, error) {
	explicitURL = strings.TrimSpace(explicitURL)
	if explicitURL != "" {
		return connectTarget{url: explicitURL}, nil
	}

	node = strings.TrimSpace(node)
	if node == "" {
		return connectTarget{}, fmt.Errorf("node must not be empty")
	}
	if strings.Contains(node, "://") {
		return connectTarget{url: node}, nil
	}

	if nctx, err := natscontext.New(node, true); err == nil {
		return contextConnectTarget(nctx)
	} else {
		return connectTarget{}, fmt.Errorf("resolve node %q: %w", node, err)
	}
}

func contextConnectTarget(nctx *natscontext.Context) (connectTarget, error) {
	options, err := nctx.NATSOptions()
	if err != nil {
		return connectTarget{}, err
	}
	return connectTarget{name: nctx.Name, url: nctx.ServerURL(), options: options}, nil
}
