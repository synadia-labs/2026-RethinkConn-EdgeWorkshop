# RethinkConn Edge Workshop

Hands-on NATS labs focused on hub/leaf topologies, subject interest propagation,
permissions, system account visibility, and JetStream edge patterns.

Each runnable lab keeps its own NATS server configs. The `workshop.sh` helper
starts the same `nats-server -c <config>` commands shown in the lab READMEs.

## Requirements

- NATS server 2.12+ for most labs; 2.14+ is recommended.
- NATS CLI.
- `jq` for the inspection commands used in several labs.
- Bash, for the local process helper.

## NATS CLI Contexts

Most labs use these contexts:

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

See [Lab 00 - Setup](Lab%2000%20-%20Setup/README.md) for the original setup notes.

## Lab Directory Map

| Directory | Lab |
| --- | --- |
| [Lab 00 - Setup](Lab%2000%20-%20Setup/README.md) | General setup |
| [Lab 01 - Same Cluster Name](Lab%2001%20-%20Same%20Cluster%20Name/README.md) | Leafs using same cluster name |
| [Lab 02 - Different Cluster Names](Lab%2002%20-%20Different%20Cluster%20Names/README.md) | Leafs using different cluster names |
| [Lab 03 - Interest Propagation](Lab%2003%20-%20Interest%20Propagation/README.md) | Subject interest propagation side lab |
| [Lab 04 - Isolate](Lab%2004%20-%20Isolate/README.md) | Isolate east-west traffic |
| [Lab 05 - Isolate and Request Isolation](Lab%2005%20-%20Isolate%20and%20Request%20Isolation/README.md) | More on `isolate` and `request_isolation` |
| [Lab 06 - Remote Leaf Isolation (Reverse Hub)](Lab%2006%20-%20Remote%20Leaf%20Isolation/README.md) | Reverse leaf connections with remote isolation |
| [Lab 07 - Block Subjects](Lab%2007%20-%20Block%20Subjects/README.md) | Block subjects north-south |
| [Lab 08 - SYS Account](Lab%2008%20-%20SYS%20Account/README.md) | SYS account leaf connection |
| [Lab 09 - SYS Account Limits](Lab%2009%20-%20SYS%20Account%20Limits/README.md) | SYS account leaf connection with restrictions |
| [Lab 10 - JetStream Subject Leak](Lab%2010%20-%20JetStream%20Subject%20Leak/README.md) | JetStream captured-subject leak |
| [Lab 11 - JetStream Domain Lottery](Lab%2011%20-%20JetStream%20Domain%20Lottery/README.md) | JetStream domain lottery |
| [Lab 12 - Locked Down Leafs](Lab%2012%20-%20Locked%20Down%20Leafs/README.md) | Locked down leafs |
| [Lab 13 - Reserved](Lab%2013%20-%20Reserved/README.md) | Reserved |
| [Lab 14 - Remote Leaf Streams](Lab%2014%20-%20Remote%20Leaf%20Streams/README.md) | Hub remote access to leaf streams |
| [Lab 15 - Stream Sources](Lab%2015%20-%20Stream%20Sources/README.md) | Hub sources and merges leaf streams |
| [Lab 16 - Explicit Consumers](Lab%2016%20-%20Explicit%20Consumers/README.md) | Hub sources and merges leaf streams with explicit consumers |
| [Lab 17 - Device Republish](Lab%2017%20-%20Device%20Republish/README.md) | Target devices individually with stream republish |
| [Lab 18 - Leaf Connect Disconnect](Lab%2018%20-%20Leaf%20Connect%20Disconnect/README.md) | Hot reload leaf connection changes |
| [Lab 19 - JWT Default User](Lab%2019%20-%20JWT%20Default%20User/README.md) | Decentralized auth default user behavior |

## Run With Local NATS Servers

Use the bash helper from the repository root:

```sh
./workshop.sh start 1
./workshop.sh logs
./workshop.sh status 1
./workshop.sh stop 1
```

The helper runs `nats-server -c <config>` in the lab directory, so relative
JetStream stores such as `./js/l1` behave the same as when you run the commands
by hand.

The direct equivalent, from a lab directory, is to run each server in its own
terminal:

```sh
nats-server -c hub.conf
nats-server -c l1.conf
nats-server -c l2.conf
nats-server -c l3.conf
```

The script accepts lab numbers, `labN` ids, or formal directory names.

Runtime pid files and logs are written under the repository `.workshop/`
directory. `./workshop.sh logs` follows the current running lab's logs and
prints the lab name at the top of the output.

## Cleanup

For local processes:

```sh
./workshop.sh clean 1
```

JetStream labs write stores under each lab's `js/` directory. The local helper's
`clean` command removes that store for the selected lab.