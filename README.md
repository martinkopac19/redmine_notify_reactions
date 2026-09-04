# Redmine Notify Reactions

Redmine 6 lets people give a **thumbs up** to an issue, a comment, a forum post
or a news item — and then tells nobody about it. The author only finds out if
they happen to open the page again.

This plugin sends the author a short e-mail.

## What it does

- **Like on an issue** → e-mail to the issue author.
- **Like on a comment** → e-mail to the person who wrote the comment.
- The same applies to **forum posts**, **news items** and **comments on news**,
  because Redmine allows reactions there too.
- The e-mail is deliberately short: who liked it, what it was, a link straight
  to it, and — for comments and posts — the first 300 characters of the liked
  text, so it is clear which one it was.
- It joins the mail thread of the issue (or news item, or topic) it belongs to,
  so it does not sit alone in the mailbox.

## What it does not do

- **No e-mail for liking your own thing.** Nobody needs to hear about that.
- **No e-mail when a like is removed.** Taking a thumbs up back is not news.
- **A repeated like sends another e-mail.** If somebody removes their like and
  gives it again, that is a new like and it is announced again. There is no
  cooling-off period; this was a conscious decision, on the grounds that an
  internal team does not toggle likes for sport. Should it ever become a
  problem, the place to change it is `NotifyReactions.deliver`.

## What it respects

- **"No events"** in a user's profile means no e-mail, always.
- Locked accounts and people who cannot see the liked object are never notified.
- If reactions are switched off in Administration → Settings → Display, nothing
  happens at all — there is nothing to react to.
- Other notification preferences (for example *"Only issues I am assigned to"*)
  are not consulted: a like is always about your own issue or your own comment,
  so those filters have nothing to say about it.

## Configuration

Administration → Plugins → Notify reactions. A single on/off switch. The page
warns you if reactions themselves are disabled in Redmine.

## Requirements

- Redmine **6.0+** — earlier versions have no reactions at all.
  Developed and tested on **6.1.3**.
- No migrations, no changes to Redmine core: the plugin only adds an
  `after_create_commit` callback to `Reaction` and one action to `Mailer`.

## Self-test

```
docker compose exec -T --user redmine -e SECRET_KEY_BASE=<key> redmine \
  bin/rails runner -e production plugins/redmine_notify_reactions/extra/selftest.rb
```

16 checks: both kinds of like, the recipient, the subject, the link, the
excerpt, self-likes, "No events", the off switch, removing a like and liking
again. The test cannot run inside a transaction — the plugin hangs off
`after_create_commit`, which never fires on rollback — so it creates real rows
in `reactions` and deletes them again in an `ensure` block. Nothing else in the
database is touched.

## Licence

GPL-2.0, same as Redmine.
