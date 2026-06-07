# Lab #7 SYS account leaf connection

- Leaf connect the system account in addition to the application account
- Opens the door to monitor from the hub all kind of system events in the leafs, as well as invoking system services
- Details on events and services: [https://docs.nats.io/running-a-nats-service/configuration/sys_accounts]
- Without system account, observability would need Prometheus Exporter / NATS Surveyor as a side-car of each NATS server
- With system account connected, observability can leverage a single NATS Surveyor to monitor the full topology

---

## System account goodies

```sh
# see all the servers in the topology, from the hub...
nats --context syshub server ls
# ...or from a leaf
nats --context sysl1 server ls
```

A few useful commands to inspect connections and subscriptions:

```sh
nats context select syshub
nats server report connections
nats server request connections --subscriptions
nats server request gateways --subscriptions
nats server request leafnodes --subscriptions
nats server request routes --subscriptions
nats server request subscriptions --detail
```

In labs #1 and #2 we used `curl` to get insight on subscriptions using the http port in _each_ server.
Now we can do the same for the _full_ topology with a _single query_ in the system account!:

```sh
nats --context syshub server ls --json | 
jq '.[] | {
  server: .server.name,
  subscriptions: .statsz.subscriptions
}'
```

Detailed report of local subscriptions in each server:

```sh
nats --context syshub server request subscriptions --detail | 
jq -r '
"SERVER: \(.server.name)
SUBSCRIPTIONS: \(.data.num_subscriptions)
SUBJECTS:
\(
  .data.subscriptions_list
  | map("  - " + .subject)
  | join("\n")
)

"
'
```

Detailed report of subscriptions from leafnodes in each server:

```sh
nats --context syshub server request leafnodes --subscriptions | 
jq -r '
.server.name as $server
| .data.leafs[]
| "SERVER: \($server)\nLEAF FROM: \(.name)\nACCOUNT: \(.account)\nNUM_SUBSCRIPTIONS: \(.subscriptions)\n"
  + (.subscriptions_list | map("  " + .) | join("\n"))
  + "\n"
'
```

---

## Too much visibility on the leafs? Too many leafs & events? --> limit with permissions

We have seen that the leafs can also get information about the full topology, something not always dessirable:

```sh
nats --context sysl1 server ls
```

Check the system service used by `nats server ls` adding option `--trace`

```sh
nats --context sysl1 server ls --trace
```

All we need to do is limit permissions for the leaf user in the system account to restrict events and service calls as needed.

Next Lab (#8) shows an example with SYS sharing restriction.

---
