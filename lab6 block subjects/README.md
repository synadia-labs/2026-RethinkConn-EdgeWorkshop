# Lab #6 - Block subjects (North-South)

There are two ways to block subjects for North-South traffic:

1. On the hub side ---> permissions for the leaf user (pub/sub allow/deny `permissions`)
2. On the leaf side ---> deny lists in the remote (`remotes[].deny_imports/deny_exports`

They can be combined.
Both sides have this way control, though hub-side permissions are a bit more flexible.
Additionally both hub and leafs will do a best effort to avoid interest propagation message exchanges based on these blocks. 

In the lab we always use the leaf as the reference point:

- publish: leaf --> hub
- subscribe:  leaf <-- hub

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

The lab uses `deny` permissions to match semantics with leaf side `deny_export/import`. But it is a good practice to use `allow` permissions, as that block everything else.
In general, *block everything leaf-hub and then unblock just what is needed* is a good security practice, and provides tighter control on interest propagation exchanges.

---

## More on interest propagation (extended lab)




But:

On 1. No attempt to propagate interest --> the hub tells the leaf about pub/sub restrictions during connect time (no way to monitor with -DVV, but the hub->leaf traffic shows that the hub actually sends the list of permissions to the leaf), so this can block locally efficiently

On 2. leaf->hub pub deny (with deny_exports) does not block interest prop: the hub tries to send the interest LS+ msg to the leaf, than then rejects it. So not efficient.  If Debug is enabled, the leaf logs this: [DBG] Permissions Violation for Subscription to "nopub.foo"  

On 2. leaf->hub sub deny (with deny_imports) blocks directly at the leaf, so it is efficiently handled!

In summary:

- Hub permissions are handled efficiently both ways.  
- Leaf side blocking produces the same outcome, but hub subscriptions where leaf->to->hub publication is blocked with deny_exports are not handled efficiently (wasted interest prop LS+ messages). Oposite direction (deny_imports) is efficient.

Blocking msgs going hub->leaf any of the two is good (hub-side perms or deny_imports)
Blocking msgs going leaf->hub better use hub-side permissions (vs deny_exports)

```sh
# run servers with tracing
# terminal 1
nats-server -c h.conf --trace  # blocks!
# terminal 2
nats-server -c l1.conf --trace  # blocks!
# terminal 3
nats-server -c l2.conf --trace  # blocks!
# terminal 4
nats-server -c l3.conf --trace  # blocks!

nats context add h --server=h:x@:4222 
nats context add l1 --server=e:x@:4232 
nats context add l2 --server=e:x@:4242 
nats context add l3 --server=e:x@:4252 


nats --context h sub "nopub"
nats --context l1 sub "nopub"
nats --context l2 sub "nopub"
nats --context l3 sub "nopub"

nats --context h sub "nosub"
nats --context l1 sub "nosub"
nats --context l2 sub "nosub"
nats --context l3 sub "nosub"



nats --context h pub nopub "h: nopub"
nats --context l1 pub nopub "l1: nopub"
nats --context l2 pub nopub "l2: nopub"
nats --context l3 pub nopub "l3: nopub"

nats --context h pub nosub "h: nosub"
nats --context l1 pub nosub "l1: nosub"
nats --context l2 pub nosub "l2: nosub"
nats --context l3 pub nosub "l3: nosub"
```

----




Same outcome for 



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


nats --context h sub "nopub"
nats --context l1 sub "nopub"
nats --context l2 sub "nopub"
nats --context l3 sub "nopub"

nats --context h sub "nosub"
nats --context l1 sub "nosub"
nats --context l2 sub "nosub"
nats --context l3 sub "nosub"



nats --context h pub nopub "h: nopub"
nats --context l1 pub nopub "l1: nopub"
nats --context l2 pub nopub "l2: nopub"
nats --context l3 pub nopub "l3: nopub"

nats --context h pub nosub "h: nosub"
nats --context l1 pub nosub "l1: nosub"
nats --context l2 pub nosub "l2: nosub"
nats --context l3 pub nosub "l3: nosub"
```
