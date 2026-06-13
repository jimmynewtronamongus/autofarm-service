# Grow a Garden 2 Autofarm Hub

`Main.server.lua` is the executor/local GUI loader. It only runs on the client.

For buttons to affect gameplay in your own game, add `ServerBridge.server.lua` to `ServerScriptService` and put your Roblox user id in `OWNER_USER_IDS`.

## Server Action Bindables

`ServerBridge.server.lua` creates this folder:

`ServerScriptService.DevScriptHubActions`

Wire these `BindableFunction` objects to your own game systems:

- `CollectFruit(player, radius)` -> return collected count or `true`
- `PlaceSeed(player, seedName)` -> return `true` when a seed is placed
- `SellInventory(player)` -> return `true` when sold
- `BuySeed(player, seedName, amount)` -> return `true` when bought

The executor GUI sends only high-level requests. The server bridge performs permission checks and owns the real gameplay actions.
