# Mux Responders Tool

Hosts simulated request responders on a leaf server. By default, each simulated
client subscribes once per backing service:

```text
client.001.X
client.001.Y
client.001.Z
```

With `--mux`, each client subscribes once with a wildcard and routes the suffix
to the matching backing service:

```text
client.001.>
```

Run from the repository root:

```sh
go run tools/responders/main.go
go run tools/responders/main.go --node=l2
go run tools/responders/main.go --mux
go run tools/responders/main.go --clients=25 --services=X,Y,Z --mux
```

Useful with `scripts/monitor.sh` while a lab topology is running.
The default node is `l1`. Node names resolve through matching NATS CLI
contexts when present, with workshop defaults for `hub`, `l1`, `l2`, and `l3`.
Use `--url` for an explicit server URL.

Options:

```sh
go run tools/responders/main.go --help
```
