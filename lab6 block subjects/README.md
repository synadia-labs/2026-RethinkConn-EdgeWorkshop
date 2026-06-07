# Lab #6 - Block subjects (North-South)

There are two ways to block subjects for North-South traffic:

1. On the hub side ---> permissions for the leaf user (pub/sub allow/deny `permissions`)
2. On the leaf side ---> deny lists in the remote (`remotes[].deny_imports/deny_exports`

They can be combined.
This way both sides have some control, though hub-side permissions are a bit more flexible.
Additionally both hub and leafs will do a best effort to avoid interest propagation message exchanges based on these.

In this Lab we always use the leaf as the reference point:

- publish: leaf --> hub
- subscribe:  leaf <-- hub

Review the server config files:

- leaf 2 is restricted for pub/sub in a couple subjects using permissions.
- leaf 3 has similar restrictions, but using deny_import/export on the leaf side.

---

## Testing north-south traffic block

Test publishing (messages leaf --> hub)

```sh
# Create subscribers in multiple terminals
nats --context hub sub nopub.foo
nats --context l1  sub nopub.foo
nats --context l2  sub nopub.foo
nats --context l3  sub nopub.foo

# Publish messages 
nats --context hub pub nopub.foo  "h: nopub"
nats --context l1  pub nopub.foo  "l1: nopub"
nats --context l2  pub nopub.foo  "l2: nopub"
nats --context l3  pub nopub.foo  "l3: nopub"
```

Test subscription (messages leaf <-- hub)

```sh
# Create subscribers in multiple terminals
nats --context hub sub nosub.foo
nats --context l1  sub nosub.foo
nats --context l2  sub nosub.foo
nats --context l3  sub nosub.foo

# Publish messages
nats --context hub pub nosub.foo  "h: nosub"
nats --context l1  pub nosub.foo  "l1: nosub"
nats --context l2  pub nosub.foo  "l2: nosub"
nats --context l3  pub nosub.foo  "l3: nosub"
```

Outcomes:

Same results for both permissions or deny_export/import (same results in both leaf 2 and leaf3).

The lab uses `deny` permissions to match semantics with leaf side `deny_exports/imports`. But it is a good practice to use `allow` permissions, as that block everything else.
In general, *block everything leaf-hub and then unblock just what is needed* is a good security practice, and provides tighter control on interest propagation exchanges.

---

## More on interest propagation (extended lab)

When subjects are blocked across the leaf nodes connections, the servers will also optimize the exchange of interest propagation messages (`LS+/LS-`).
The only exception is `deny_exports` (as of NATS 2.14.2.  This could be optimized in the future).

We can explore the details starting the servers in trace mode:

```sh
# run servers with tracing
# terminal 1
nats-server -c hub.conf --trace  # blocks!
# terminal 2
nats-server -c l1.conf --trace  # blocks!
# terminal 3
nats-server -c l2.conf --trace  # blocks!
# terminal 4
nats-server -c l3.conf --trace  # blocks!
```

### Subscribing

The hub tells the leaf 2 about subscription restrictions during connect time. This is not shows in the logs (neither with tracing nor logging) but the exchange is there, during connect time. That way the leaf is aware of sub restrictions on the hub side and will avoid unnecesary `LS+` messages.

```sh
# This one will trace an LS+ going up to the hub (and down to other leafs as east-west is open in this setup)
nats --context l2 sub foo 
# But this one will skip that interest exchange: the leaf is aware of its permissions on the hub-side and knows the subscription would be blocked
nats --context l2  sub nosub.foo
```

In the case of leaf 3, it is aware of its own import restriction and we'll get similar results:

```sh
# This one will trace an LS+ going up to the hub (and down to other leafs as east-west is open in this setup)
nats --context l3 sub foo 
# But this one will skip that interest exchange: the leaf is aware of its own deny_imports
nats --context l3  sub nosub.foo
```

### Publishing

The hub is aware of the publish restrictions imposed to leaf 2 and skip interest propagation accordingly:

```sh
# This one will trace an LS+ going down to the leaf 2
nats --context hub sub foo 
# But this one will skip that interest exchange with leaf 2, as the hub knows the permissions for the leaf 2 user
nats --context hub  sub nopub.foo
```

In the case of leaf 3, the hub is not currently aware of the leaf side deny_exports:

```sh
# This one will trace an LS+ going down to the leaf 3
nats --context hub sub foo 
# And this one also shows an LS+ going down to the leaf 3, though we know the leaf will reject it 
nats --context hub  sub nopub.foo
```

In fact, if we restart leaf 3 with both tracing and debug enabled, we'll see the local rejection of that LS+ request (Permissions Violation for Subscription to "nopub.foo"):

```sh
nats-server c l3.conf --trace --debug
```

### Wildcards / larger subject sets

Note that subject patterns with a larger subject space will still trigger `LS+/LS-` interest exchanges.

Try for example

```sh
nats --context sub sub ">"
```

and inspect the tracing messages in the leafs server consoles.

Blocking will be done at message level case by case, based on leaf user permissions and deny_imports/exports then.

---

In summary:

- Hub permissions handle interest propagation efficiently both ways.  
- Leaf side `deny_exports` are not handled so efficiently (wasted interest prop. `LS+` messages). Oposite direction (`deny_imports`) is efficient.
- Wildcard patterns for larger subject spaces will still trigger interest exchanges, blocking is decided individually at message level then.

---
