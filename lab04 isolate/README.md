# Lab #4 - Isolate (East-West)

Leafs using unique cluster names, but we want to disable East-west traffic.

Instead of switching to same cluster name (old workaround), NATS 2.12 onwards provide the `leafnodes.isolate: true` option for this

This lab is similar to Lab #2, but with that option in the hub leafnodes section:

```json
leafnodes {
  port: 7422
  isolate: true
}
```

There are some subtle differences between isolate and same-cluster-names. Covered in Lab #5.

---
