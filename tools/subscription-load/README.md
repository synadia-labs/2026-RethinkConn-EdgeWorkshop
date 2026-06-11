# Subscription Load Tool

Creates many unique subscriptions against a NATS server and holds them open.
This is useful when a lab needs visible subject-interest growth in
`scripts/monitor.sh`.

```sh
go run tools/subscription-load/main.go --url=nats://e:x@127.0.0.1:4232 --count=1000 --prefix=edge.device
```

Subjects are created as:

```text
edge.device.000001.status
edge.device.000002.status
...
```

Options:

```sh
go run tools/subscription-load/main.go --help
```
