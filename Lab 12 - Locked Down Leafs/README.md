# Lab #12 - Locked down leafs

- Not really a lab, but a starting point to unlock subjects as needed in the next few labs.
- Hub + leafs, different cluster names, East-West disabled.
- North-South all locked down, except a couple subjects.
- Whenever unlocking any new subjects --> consider the implications: cardinality, frequency of sub/unsub...
- Alternative: leave everything open (up to security boundaries), perform subject interest analysis _under load or real deployment_, and tune based on that.

---

In this example only `l2h.>` is open (leaf --> hub) and `h2l.>` (hub --> leaf).

Enless variations are possible, for example specify per-leaf permissions such as:

- publish allow `l2h.l1.>`  and subscribe allow `h2l.l1.>`  to enforce leaf 1 origin/destination for extra traceability/security (adjust permissions accordingly in all the leafs)
- Enabling east-west (`isolate:false`) and publish allow `l2l.l1.*.>` and subscribe allow `l2l.*.l1.>` to get  directed leaf-to-leaf flows
- extend the previous with publish allow `l2l.l1.all.>` and subscribe `l2l.*.all.>` to allow leaf to _all_ leafs comms
- Decentralized auth (operator mode) with scoped keys brings in extra power templaing all the previous with signing keys (all leafs will follow the same pattern, permissions will adapt to leaf ID) [https://docs.nats.io/using-nats/nats-tools/nsc/signing_keys#template-functions]

All this is core nats. JetStreams will open another world of possibilities.

---

## Setup

```sh
../workshop.sh start 12
```

Direct equivalent, from this lab directory:

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

---

## JetStreams - what to unlock?

Cross-domain JetStream access will need some subjects open leaf->hub and hub->leaf.

JetStream API is documented (mostly...): [https://docs.nats.io/reference/reference-protocols/nats_api_reference]

Docs are not perfect, something that will help _a lot_ with any loose ends --> Keep these running while testing/debugging issues:

```sh
# in different terminals:
nats --context hub sub '>'
nats --context l1  sub '>'
```

This will help detecting protocol messages seen in one side but not on the other and insight on the subjects that need to poke trough!

---

## `_INBOX.>`

- It is almost unavoidable opening this one in both directions, but depends on the use of custom subject prefixes.
- This is usually a high cardinality & high frequency (sub/unsub) subject set --> memory pressure (interest graphs) in the servers, potentially network pressure.
- Inbox multiplexing and custom inbox prefixes may help to minimize impact.
- Some upcoming improvements in NATS will make this trivial.

---
