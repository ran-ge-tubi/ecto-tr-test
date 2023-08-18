import Config

config :friends, Friends.Repo,
  database: "friends_repo",
  username: "range",
  password: "",
  hostname: "localhost"
  
config :friends, ecto_repos: [Friends.Repo]
