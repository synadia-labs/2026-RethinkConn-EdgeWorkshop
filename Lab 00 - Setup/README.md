# Lab #0 - General setup

- We'll use a hub and 3 leafs, local processes. No docker or k8s needed.
- Single node each for simplicity (both hub and leafs can be easily extended to be clusters with multiple nodes)
- Using standard ports (nats-client:4222, leaf-node:7222, http:8222), each leaf adds +10 to those (:4232, :4242, etc)
- Simple auth model (user/pwd). Hubs and each leaf may use other model as you wish

---

## Requirements

- nats-server --> NATS 2.12+ is enough in most cases. Some of the JetStream examples may require NATS 2.14+, so better get that one if possible.
- nats-cli --> get latest 0.4.x
- jq
- terminal --> (we assume Linux or macOS). Windows WSL should work but is untested.

---

## Setup

```sh
$ ../workshop.sh setup
```

### Manual Setup

Define a few nats-cli connection contexts

```sh
nats context add hub --server a:x@:4222
nats context add l1 --server e:x@:4232
nats context add l2 --server e:x@:4242
nats context add l3 --server e:x@:4252
nats context add syshub --server s:x@:4222
nats context add sysl1 --server s:x@:4232
nats context add sysl2 --server s:x@:4242
nats context add sysl3 --server s:x@:4252
```

To cleanup contexts

```sh
nats context rm -f hub
nats context rm -f l1
nats context rm -f l2
nats context rm -f l3
nats context rm -f syshub
nats context rm -f sysl1
nats context rm -f sysl2
nats context rm -f sysl3
```

---

## NATS servers

To run the nats servers:

```sh
nats-server -c hub.conf &
nats-server -c l1.conf &
nats-server -c l2.conf &
nats-server -c l3.conf &

# make sure they all 4 are running
jobs
```

Make sure to start the servers in the right directory. Each lab will use its own config files (unless otherwise noted).

In some labs we'll run these with tracing enabled using option `--trace` or adding `trace:true` to the .conf file.

Stopping servers, this is the lazy but easy way:

```sh
killall nats-server
```

In some labs you may have left behind some nats-cli clients dangling around that interfere with subsequent labs.
If so, clean them up too:

```sh
killall nats
```

For tests using JetStreams, a final cleanup of stores is needed:

```sh
rm -Rf ./js
```

---
