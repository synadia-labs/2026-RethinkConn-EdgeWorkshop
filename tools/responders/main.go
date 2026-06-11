package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/nats-io/jsm.go/natscontext"
	"github.com/nats-io/nats.go"
)

type clientHandle struct {
	id   int
	nc   *nats.Conn
	subs []*nats.Subscription
}

func main() {
	var (
		node          = flag.String("node", "l1", "NATS CLI context or workshop node name for simulated clients")
		serverURL     = flag.String("url", "", "explicit NATS server URL for simulated clients; overrides --node")
		clients       = flag.Int("clients", 100, "number of simulated leaf clients")
		serviceList   = flag.String("services", "X,Y,Z", "comma-separated backing service names per client")
		subjectPrefix = flag.String("subject-prefix", "client", "request subject prefix")
		mux           = flag.Bool("mux", false, "use one wildcard request subscription per client")
		duration      = flag.Duration("duration", 0, "run duration; 0 runs until interrupted")
	)
	flag.Parse()

	if *clients <= 0 {
		log.Fatal("clients must be greater than zero")
	}

	services := parseServices(*serviceList)
	if len(services) == 0 {
		log.Fatal("at least one service is required")
	}

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	target, err := resolveConnectTarget(*node, *serverURL)
	if err != nil {
		log.Fatal(err)
	}

	handles, err := startClients(target, *subjectPrefix, *clients, services, *mux)
	if err != nil {
		log.Fatal(err)
	}
	defer closeClients(handles)

	subCount := *clients * len(services)
	mode := "multiple inboxes"
	if *mux {
		mode = "muxed inbox"
		subCount = *clients
	}

	fmt.Printf("mode=%s clients=%d services=%s expected_leaf_subscriptions=%d\n",
		mode, *clients, strings.Join(services, ","), subCount)
	fmt.Printf("connected_to=%s\n", target.description())
	if *mux {
		fmt.Printf("each client subscribes to %s.<client>.> and routes the suffix to a backing service\n", *subjectPrefix)
	} else {
		fmt.Printf("each client subscribes to one subject per backing service under %s.<client>.<service>\n", *subjectPrefix)
	}
	fmt.Println("run scripts/monitor.sh from the repository root in another terminal to watch leaf interest")
	fmt.Println()
	fmt.Println("try these requests from another terminal:")
	printRequestExamples(*subjectPrefix, services)
	fmt.Println()

	if *duration > 0 {
		select {
		case <-ctx.Done():
		case <-time.After(*duration):
		}
	} else {
		<-ctx.Done()
	}
}

func parseServices(raw string) []string {
	parts := strings.Split(raw, ",")
	services := make([]string, 0, len(parts))
	seen := map[string]struct{}{}

	for _, part := range parts {
		service := strings.TrimSpace(part)
		if service == "" {
			continue
		}
		if _, ok := seen[service]; ok {
			continue
		}
		seen[service] = struct{}{}
		services = append(services, service)
	}

	return services
}

func startClients(target connectTarget, prefix string, clients int, services []string, mux bool) ([]*clientHandle, error) {
	handles := make([]*clientHandle, 0, clients)

	for id := 1; id <= clients; id++ {
		opts := make([]nats.Option, 0, len(target.options)+2)
		opts = append(opts, target.options...)
		opts = append(opts,
			nats.Name(fmt.Sprintf("responder-client-%03d", id)),
			nats.NoReconnect(),
		)
		nc, err := nats.Connect(target.url, opts...)
		if err != nil {
			closeClients(handles)
			return nil, fmt.Errorf("connect client %03d: %w", id, err)
		}

		handle := &clientHandle{id: id, nc: nc}
		if mux {
			if err := subscribeMux(handle, prefix, services); err != nil {
				nc.Close()
				closeClients(handles)
				return nil, err
			}
		} else if err := subscribeSeparate(handle, prefix, services); err != nil {
			nc.Close()
			closeClients(handles)
			return nil, err
		}

		if err := nc.Flush(); err != nil {
			nc.Close()
			closeClients(handles)
			return nil, fmt.Errorf("flush client %03d: %w", id, err)
		}

		handles = append(handles, handle)
	}

	return handles, nil
}

func subscribeSeparate(handle *clientHandle, prefix string, services []string) error {
	for _, service := range services {
		service := service
		subject := requestSubject(prefix, handle.id, service)
		sub, err := handle.nc.Subscribe(subject, func(msg *nats.Msg) {
			respond(msg, handle.id, service)
		})
		if err != nil {
			return fmt.Errorf("subscribe client %03d subject %s: %w", handle.id, subject, err)
		}
		handle.subs = append(handle.subs, sub)
	}

	return nil
}

func subscribeMux(handle *clientHandle, prefix string, services []string) error {
	allowed := make(map[string]struct{}, len(services))
	for _, service := range services {
		allowed[service] = struct{}{}
	}

	base := clientPrefix(prefix, handle.id)
	subject := base + ".>"
	sub, err := handle.nc.Subscribe(subject, func(msg *nats.Msg) {
		service := strings.TrimPrefix(msg.Subject, base+".")
		if service == msg.Subject || service == "" {
			respondUnknown(msg, handle.id, "missing service suffix")
			return
		}
		if _, ok := allowed[service]; !ok {
			respondUnknown(msg, handle.id, "unknown service "+service)
			return
		}
		respond(msg, handle.id, service)
	})
	if err != nil {
		return fmt.Errorf("subscribe client %03d subject %s: %w", handle.id, subject, err)
	}
	handle.subs = append(handle.subs, sub)

	return nil
}

func respond(msg *nats.Msg, clientID int, service string) {
	if msg.Reply == "" {
		return
	}
	response := fmt.Sprintf("hello from service %s on client %03d", service, clientID)
	_ = msg.Respond([]byte(response))
}

func respondUnknown(msg *nats.Msg, clientID int, reason string) {
	if msg.Reply == "" {
		return
	}
	response := fmt.Sprintf("client %03d cannot route request: %s", clientID, reason)
	_ = msg.Respond([]byte(response))
}

func clientPrefix(prefix string, id int) string {
	return strings.TrimRight(prefix, ".") + "." + fmt.Sprintf("%03d", id)
}

func requestSubject(prefix string, id int, service string) string {
	return clientPrefix(prefix, id) + "." + service
}

func printRequestExamples(prefix string, services []string) {
	for i, service := range services {
		if i >= 3 {
			break
		}
		fmt.Printf("  nats --context hub request %s ''\n", requestSubject(prefix, i+1, service))
	}
}

func closeClients(handles []*clientHandle) {
	for _, handle := range handles {
		if handle == nil || handle.nc == nil {
			continue
		}
		for _, sub := range handle.subs {
			_ = sub.Unsubscribe()
		}
		handle.nc.Close()
	}
}

func init() {
	flag.CommandLine.SetOutput(os.Stdout)
	flag.Usage = func() {
		fmt.Fprintf(flag.CommandLine.Output(), "Usage: %s [options]\n\n", os.Args[0])
		flag.PrintDefaults()
		fmt.Fprintln(flag.CommandLine.Output())
		fmt.Fprintln(flag.CommandLine.Output(), "Examples:")
		fmt.Fprintln(flag.CommandLine.Output(), "  go run tools/responders/main.go --clients=100")
		fmt.Fprintln(flag.CommandLine.Output(), "  go run tools/responders/main.go --node=l2 --clients=100")
		fmt.Fprintln(flag.CommandLine.Output(), "  go run tools/responders/main.go --clients=100 --mux")
	}
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
