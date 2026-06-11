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
- Go (for some labs)
- terminal --> (we assume Linux or macOS). Windows WSL should work but is untested.

---

## Setup

```sh
../workshop.sh setup
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

To run the NATS servers for a lab, use the workshop helper from that lab
directory:

```sh
../workshop.sh start <lab-number>
../workshop.sh logs
```

Each lab uses its own config files. The helper starts `nats-server -c <config>`
from the lab directory.

The direct equivalent is to run each server config from the lab directory, one
per terminal:

```sh
# terminal 1
nats-server -c hub.conf
# terminal 2
nats-server -c l1.conf
# terminal 3
nats-server -c l2.conf
# terminal 4
nats-server -c l3.conf
```

In some labs we'll run these with tracing enabled:

```sh
../workshop.sh restart <lab-number> --trace
../workshop.sh logs
```

Or directly:

```sh
nats-server -c hub.conf --trace
nats-server -c l1.conf --trace
nats-server -c l2.conf --trace
nats-server -c l3.conf --trace
```

Stopping servers:

```sh
../workshop.sh stop <lab-number>
```

In some labs you may have left behind some nats-cli clients dangling around that interfere with subsequent labs.
If so, clean them up too:

```sh
killall nats
```

For tests using JetStreams, a final cleanup of stores is needed:

```sh
../workshop.sh clean <lab-number>
```

---
