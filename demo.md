

1. Create a VM
   * https://lightsail.aws.amazon.com/ls/webapp/home/instances
   * echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCyAUow0SsQ+aiNfhxtRQxVe7FxQmHErrtZX8XC2qNnah0avftsFpIrn3VEVEYLEPYCpkasv1bEJgnw5aWRrniCcaA+Emx1bEX6OyB+jc/wgGv2v2JsiEUzlXgre2Ijj0vsR1IvjUW/Wwj4V4zg33hYYDxVhiCb+vUlGHyV5cWAEAnLpSaCXR/2G3zvKWHSII+wh+VcMtKfAwxVeaoQ+p2lvy3qvWlKp0gtNjaSrDK2t4FhJgSYSv68xW9Fk0BJpFZAXEai/mVU4ULZuVVWkSMnzN9EzsyHh4jSO8DurMjENmodzoxEJHi4fgP6JE/wvvevUIxIxxh/GHOA84wiJJyq+SBAOEv3kW14k+MmvuZZtwJ4bxXpXX6wKgsKehZMQGdKVVny2TbGZBogDf43O/j3iRs7Q6KUtTbVvflzhO74W3DXUF2aOAj8rFjharXUu2DHnFwE1vJOXJmDCMu+87zfxvQ31iHtNVXQCmX5aHYPgwkPnGwL9xG6oYPNPBUrHltrkFb9W6oLOCYWGm3G1mJOOL4vOowVVZiGZ0C7PNGvRFWCWe2kdSvTV96KCvwQJ1K3mXRkMbqQYlT00vnTcfKDEHi56IghJHkoOz6rCUOHOr2GK+VTtd0ZAoScmmYEJfSt3HGga7OpOBTVy08WoQ+qkRrXe/A79Pp46oWm0B4DKw== patryk@ipepe.pl" >> ~/.ssh/authorized_keys
   * Update firewall to allow HTTP/HTTPS
   * Update DNS (*.example.org to point to the IP)
2. Create a rails app
   * `rails new example --css=bootstrap --database=postgresql --template-engine=slim --force`
   * in `config/routes.rb` add `get "/", to: ->(_env) { [200, { "Content-Type" => "text/html" }, ["Hello, world!"]] }`
   * in `config/database.yml` set production to:
```
production:
  pool:     50
  timeout:  5000
  port:     5432
  adapter:  postgresql
  encoding: unicode
  gssencmode: disable
  database: <%= ENV.fetch('DB_NAME',     'webapp') %>
  username: <%= ENV.fetch('DB_USERNAME', 'webapp')  %>
  password: <%= ENV.fetch('DB_PASSWORD', 'Password1')  %>
  host: <%= ENV.fetch('DB_HOST',     'postgres_db') %>
```