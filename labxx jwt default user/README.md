# Decentralized authentication - `default_sentinel` to get `no_auth_user` behaviour

- NATS v2.11 added a `default_sentinel` configuration option, mostly to handle auth callout scenarios where a single auth account is enough (as a way to avoid having to distribute the sentinel bearer token to all clients)
- The feature can actually be used independently of auth callout, as a way to replicate in decent auth the `no_auth_user` feature existing in static authentication
- This no_auth_user behaviour can not be combined with auth callout -- if auth callout is enabled the `default_sentinel` will be used to route the auth callout invocation accordingly. 

----

## Runbook to test default_sentinel

Some init steps:

```sh
# Convenient alias so nsc works in the local directory
alias nsc='nsc --all-dirs ./nsc/'
mkdir -p creds/ conf/

# select the default NATS context (should be localhost:4222, in case your default one goes somewhere else act accordingly!)
nats context set default
```

Create a new Operator for our setup, with System Account

```sh
# Create a new operator
nsc add operator --generate-signing-key --sys --name MyOperator
nsc edit operator  --require-signing-keys --account-jwt-server-url "nats://localhost:4222"
```

Add a couple accounts for apps and some users

```sh
# Create application accounts, with signing keys
nsc add account APP1
nsc edit account APP1 --sk generate
nsc add account APP2
nsc edit account APP2 --sk generate

# Create also some regular users
nsc add user --account APP1 --name app1
nsc add user --account APP2 --name app2
nsc generate creds --account APP1 --name app1 > creds/app1.creds
nsc generate creds --account APP2 --name app2 > creds/app2.creds
```

Lets create a bearer JWT in APP1, we'll setup that as `default_sentinel` and effectively provide sort of a `no_auth_user` behaviour for us!!

```sh
# Auth default sentinel (default lobby pass) - must be bearer, ie. no connect challenge/secret.
nsc add user --account APP1 --bearer --name default_user
```

We have enough information to create the configuration file for the NATS server.
And we add that default user bearer JWT in the `default_sentinel` field:

```sh
# Create nats server configs, including the resolver config
echo "include resolver.conf" > conf/server.conf
nsc generate config --nats-resolver > conf/resolver.conf
echo -n "default_sentinel: "  >> conf/resolver.conf
cat nsc/MyOperator/accounts/APP1/users/default_user.jwt >> conf/resolver.conf
```

Now we are ready to start the server:

```sh
# Start the server
nats-server -c conf/server.conf &
# Load non preloaded accounts (otherwise the default user in APP1 will not work)
# (wait a couple seconds so the server fully starts)
sleep 2
nsc push -A 
```

Regular users will work normally:

```sh
# they should work as expected
nats --creds creds/app1.creds pub test 'hello from app1'
nats --creds creds/app2.creds pub test 'hello from app2'
```

And the default user will work too!!!

```sh
# it will use the default_sentinel ie. default_user bearer JWT, linked to APP1 account
nats account info
nsc describe user --account APP1 --name default_user
nsc describe account --name APP1

# Will be listening in APP1 account
nats sub test
```

Final cleanup:

```sh
#cleanup
rm -Rf nsc/ creds/ conf/ jwt/
```

----
