# Lab #20 - Muxed Request Responders

This lab shows how many edge clients, each exposing several request handlers,
can create a large amount of propagated subscription interest across a leaf
topology.

The default mode creates simulated clients on leaf 1. Each client exposes three
simple backing services, `X`, `Y`, and `Z`, using one subscription per service:

```text
client.001.X
client.001.Y
client.001.Z
```

With `--mux`, the request subject pattern stays the same, but each client uses
one wildcard subscription and dispatches the suffix to the correct backing
service:

```text
client.001.>
```

The requests still go to `client.<id>.<svc>`. Only the number of subscriptions
changes.

---

## Run The Servers

From the repository root:

```sh
./workshop.sh start 20
```

Direct equivalent from this lab directory:

```sh
nats-server -c hub.conf
nats-server -c l1.conf
nats-server -c l2.conf
nats-server -c l3.conf
```

From the repository root, watch propagated interest in another terminal:

```sh
scripts/monitor.sh
```

---

## Multiple Subscriptions Per Client

From the repository root, run the responders in default mode:

```sh
go run tools/responders/main.go
```

The app keeps 100 simulated leaf clients connected. Each client subscribes to
three request subjects, so it creates roughly 300 leaf-side subscriptions before
any requester traffic. The default target is `l1`; use `--context=l2` or
`--context=l3` to place the simulated clients on another leaf.

Send requests from another terminal:

```sh
nats --context hub request client.001.X ''
nats --context hub request client.002.Y ''
nats --context hub request client.003.Z ''
```

Expected replies:

```text
hello from service X on client 001
hello from service Y on client 002
hello from service Z on client 003
```

Leave the app running and compare the `LEAF INTEREST` column in
`scripts/monitor.sh`.

---

## Muxed Subscription Per Client

Stop the app with `Ctrl-C`, then run:

```sh
go run tools/responders/main.go --clients=25 --mux
```

Each simulated client now subscribes once:

```text
client.001.>
client.002.>
...
```

Send the same requests:

```sh
nats --context hub request client.001.X ''
nats --context hub request client.002.Y ''
nats --context hub request client.003.Z ''
```

The handler takes the suffix after `client.<id>.`, such as `X`, `Y`, or `Z`,
and dispatches to the matching backing service. The externally visible request
subjects stay the same, but propagated subscription interest drops from roughly
`clients * services` to `clients`.

---

## Key Takeaway

When creating subscriptions in an edge topology, it is easy to create a large amount of propagated
subscription interest. Muxing a single subscription can be a much more efficient pattern to reduce the
amount of propagated subscription interest.
