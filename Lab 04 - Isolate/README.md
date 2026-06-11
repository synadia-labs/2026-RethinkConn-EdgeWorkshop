# Lab #4 - Isolate (East-West)

Leafs using unique cluster names, but we want to disable East-west traffic.

Instead of switching to same cluster name (old way), NATS 2.12 onwards provide the `leafnodes.isolate: true` option for this

This lab is similar to Lab #2, but with that option in the hub leafnodes section:

```json
leafnodes {
  port: 7422
  isolate: true
}
```

```sh
../workshop.sh start 4 --trace
../workshop.sh logs
```

Direct equivalent, from this lab directory:

```sh
# terminal 1
nats-server -c hub.conf --trace
# terminal 2
nats-server -c l1.conf --trace
# terminal 3
nats-server -c l2.conf --trace
# terminal 4
nats-server -c l3.conf --trace
```

Note the lack of subject interest propagation between the leafs despite different cluster names.

```sh
nats --context l1 sub foo bar baz
```

There are some subtle differences between isolate and same-cluster-names. Covered in Lab #5.

---
