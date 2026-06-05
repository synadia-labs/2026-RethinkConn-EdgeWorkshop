# Lab #9 SYS account leaf connection with restrictions

- Similar to Lab #8, but limiting leaf<-->hub accesible services

Using permissions we can fine tune what should be shared and in what direction, both for security reasons *and/or* data volume concerns.

Check available events at the docs [https://docs.nats.io/running-a-nats-service/configuration/sys_accounts]
or just discover with `nats --context sysl1 sub '>'` and find out what to share or block.

---

## Restricted visibility

In this example we have just restricted the full set of `$SYS.REQ.>` services for the leaf-to-hub user in the system account.
The hub can use those API to query the leafs, but not the other way around:

```json
{ user: sl, password: x, permissions: { publish: { deny: ["$SYS.REQ.>"] } , subscribe: { allow: ["$SYS.REQ.>"] } } }
```

Test the outcome with:

```sh
# see all the servers in the topology, from the hub...
nats --context syshub server ls
# ...but not anymore from the leafs!
nats --context sysl1 server ls
```

There are other server initiated events (`$SYS.ACCOUNT.>`, `$SYS.SERVER.>` for example) that you should consider blocking from going down to the leafs.

In general, *block everything and then unblock just what you need* is the best way to proceed!

---
