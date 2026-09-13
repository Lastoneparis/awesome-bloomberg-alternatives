# Monetisation

## Principles

- **No pay-to-win.** Nothing bought with money affects damage, health beyond a few hit
  points, or accuracy. Operators carry passives capped at ~4% on movement and reload speed.
  Every weapon is obtainable with earned currency.
- **Odds are published and real.** The percentages shown on a crate are generated from the
  same `Rarity.dropWeight` values the roll uses. `LootCrateTests.testObservedRatesMatchPublishedOdds`
  opens 40,000 crates and asserts the observed distribution matches the published one.
- **Ads are optional and never gate progression.** Rewarded video only ever doubles
  something already earned. Interstitials never interrupt a match and are capped at one per
  five minutes.
- **Nothing expires quietly.** Purchases are non-consumable or restored via
  `Transaction.currentEntitlements` on every launch.

## Products

| Product | Type | Price | Contents |
| --- | --- | --- | --- |
| Handful of Gems | Consumable | $1.99 | 300 gems |
| Pouch of Gems | Consumable | $4.99 | 860 gems (+8%) |
| Crate of Gems | Consumable | $9.99 | 2,050 gems (+14%) |
| Case of Gems | Consumable | $19.99 | 4,800 gems (+20%) |
| Vault of Gems | Consumable | $49.99 | 13,000 gems (+30%) |
| Starter Pack | Non-consumable | $4.99 | 800 gems, 20,000 credits, a skin. One per account |
| Reaper Bundle | Non-consumable | $14.99 | Operator, legendary skin, 1,200 gems |
| Dragonlord Collection | Non-consumable | $19.99 | Legendary weapon skin, charm, spray |
| Season Pass | Consumable | $9.99 | Premium battle pass track for the season |
| Season Pass + 25 Tiers | Consumable | $24.99 | Pass plus a tier skip |
| Remove Ads | Non-consumable | $3.99 | No interstitials. Rewarded video still available |
| VIP Membership | Auto-renewable | $7.99/month | +25% XP and credits, 150 gems daily, no ads. 3-day free trial |

Larger gem packs are always better value per dollar — `ContentIntegrityTests.testStoreProductsAreCoherent`
enforces it, because a pricing ladder that inverts anywhere is misleading regardless of intent.

## Currencies

| | Earned by | Buys |
| --- | --- | --- |
| **Credits** | Playing. ~900 per 10-minute match | Weapons, attachments, most cosmetics |
| **Gems** | Purchase, battle pass, levelling | Premium cosmetics, elite crates |
| **Season Tokens** | Battle pass free track | Seasonal shop |

`Wallet.debit` is the only spend path and refuses to go negative, so no UI bug can
manufacture currency or overdraw a balance.

## Crate odds

Computed from `Rarity.dropWeight`, normalised to 100%:

| Rarity | Weight | Supply Crate |
| --- | --- | --- |
| Common | 1000 | 54.11% |
| Uncommon | 520 | 28.14% |
| Rare | 240 | 12.99% |
| Epic | 80 | 4.33% |
| Legendary | 18 | 0.97% |
| Mythic | 3 | 0.16% |

The Elite Crate is Rare-or-better, so its odds renormalise over that subset. Both are shown
in-game on the crate itself, not buried in a menu.

**Pity timer.** After 20 opens (12 for Elite) without an Epic or better, the next open is
guaranteed to be one. The counter is shown in the UI: "7 opens until a guaranteed Epic or
better". A pity system the player cannot see is just a rumour.

**Duplicates** convert to credits at the rarity's dismantle value (10 → 2,400) rather than
sitting in an inventory as dead weight.

## Battle pass

100 tiers, 1,200 XP each. Battle pass XP is earned per minute played plus a win bonus, not
per kill, so a player who spends the match capturing objectives progresses at the same rate
as one who farms kills.

- **Free track**: currency every other tier, a crate every ten, a banner at 100.
- **Premium track** ($9.99): something every tier, with signature rewards at 25 (a weapon),
  50 (an operator), 75 (a legendary skin) and 100 (a mythic operator).

A full free-track climb is roughly 45 hours across a 10-week season.

## Rewarded ads

| Placement | Reward |
| --- | --- |
| Match results | Double the credits and XP from that match |
| Daily bonus | Extra daily reward |
| Free crate | One Supply Crate |

Capped at 8 per day. Never required to progress, never shown mid-match, and disabled
entirely for VIP members and anyone who bought Remove Ads.

## App Store compliance

- **3.1.1** — Odds for every randomised item are disclosed in the purchase flow.
- **3.1.2** — Subscription price, period, auto-renewal and a link to manage it are shown
  before purchase and in Settings; a 3-day introductory trial is configured in the
  StoreKit configuration.
- **Restore** — A visible Restore Purchases button in both the store and settings.
- **Privacy** — No IDFA is requested unless ads are actually shown; the purpose string is
  honest that declining changes nothing about the game.
- **Testing** — `Support/CriticalStrike.storekit` mirrors the catalogue exactly, so the
  whole purchase flow including the subscription trial can be exercised in the simulator.
