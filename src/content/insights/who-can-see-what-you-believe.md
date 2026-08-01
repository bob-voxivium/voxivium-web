---
title: 'Who Can See What You Believe?'
description: 'Voxivium asks you to record your political positions. Here is who can see them, in plain language, and why the answer is nobody.'
publishDate: 2026-08-01
author: 'Bob Seamon'
topic: 'Methodology'
sources:
  - label: 'ISO/IEC 27018 — Protection of personally identifiable information (PII) in public clouds'
    url: 'https://www.iso.org/standard/27018'
  - label: 'NIST SP 800-122 — Guide to Protecting the Confidentiality of Personally Identifiable Information'
    url: 'https://csrc.nist.gov/pubs/sp/800/122/final'
  - label: 'Voxivium — Security'
    url: 'https://voxivium.com/security'
---

Asking someone to write down their political beliefs is asking for a lot of trust.

Most people have had the experience of hesitating before saying what they actually think about a political question, at work or at a family dinner. The hesitation is reasonable. Political opinions have cost people jobs, friendships, and worse.

So a platform that asks you to record your positions on more than a hundred policy questions is asking you to do, in writing and at scale, the thing you have learned to be careful about. It should have to explain itself.

This is that explanation. There is a [technical version](/security) with the specifics; this one is the plain-language account.

## The short answer

Nobody sees what you personally believe. Not politicians, not media organizations, not researchers, not AI labs, not campaigns.

What paying customers see is a count. A senator can learn that 72 percent of verified voters in their district support a particular position. They cannot learn that you are one of them, and there is no upgrade, no premium tier, and no partnership that unlocks it. The capability does not exist in the product.

That is a promise, and promises are worth roughly nothing on their own. The rest of this explains why the system is built so that breaking it would be difficult rather than merely against policy.

## The coat check

Here is the idea in one image.

When you check a coat, you hand over your coat and receive a numbered ticket. The rack knows that coat number 214 is a blue wool overcoat. The rack does not know it is yours. Your name lives with the attendant, on a completely different piece of paper, and the only thing connecting the two is the ticket in your pocket.

Voxivium works this way.

Your identity — your name, your date of birth, your address, the details that verify you are a real registered voter — is stored in one place. Everything you believe is stored somewhere else entirely, filed under a meaningless number rather than your name.

The two are kept in separate databases, reached with separate credentials, over separate network paths. And the connecting information was not just hidden from the belief side. It was **deleted** from it.

This matters more than it might sound. There is a large practical difference between data that is hidden and data that is absent. Hidden data can be revealed by a configuration mistake, a bug, or someone with the right permissions. Absent data cannot be revealed by anything, because it is not there.

If someone obtained a complete copy of the database holding every Voxivium user's political beliefs, they would have a very large pile of opinions attached to meaningless numbers, and no way to work out whose opinions they were.

## Why collect identity at all

A fair question: if the beliefs are what matters, why verify identity in the first place?

Because without it the numbers are worthless.

Anyone can build a website where people click buttons about politics. What comes out the other end is unusable, because there is no way to know whether the responses came from constituents, from people in another state, from someone with forty accounts, or from a script. Every online poll has this problem, which is why no serious person treats one as evidence.

Verification is what lets Voxivium say something a poll cannot: that these are real people, each counted once, each actually living in the district they are counted in. The identity check is what makes the aggregate mean anything.

So the design problem is not "should we know who you are." It is "how do we know who you are without ever being able to connect that to what you said." Separating the two is the answer.

## What happens with the sensitive parts

**Verifying your ID.** Voxivium does not do this in-house. Checking that a government ID is genuine and that a live person is holding it is a specialized job, and it is handled by a company that does only that, has passed independent security audits, and is contractually bound in how it handles the data. Voxivium receives the answer.

**Your data in transit and in storage.** Everything between your device and Voxivium is encrypted. Everything stored is encrypted, including backups.

**Who inside Voxivium can look.** Administrative access requires specific elevated permission and recent re-authentication, and every administrative action writes a permanent record of who did what and what changed. That record is written in the same operation as the change, so an action cannot happen without leaving a trace.

**Deleting your account.** Available in settings. Your positions come out of every aggregate immediately, and the underlying records are permanently deleted after a short window. The delay exists so an accidental deletion is recoverable for a limited time, not so anything can be quietly retained.

## What we will not claim

Two things worth being straight about.

**No system is perfectly secure.** Anyone who tells you their platform cannot be breached is either uninformed or selling something. What a responsible system does is limit what a breach would yield. The reason identity and belief are separated is not that Voxivium expects to be broken into. It is that if it ever were, the thing you actually care about protecting would not be sitting there ready to read.

**Voxivium has not completed formal security certification.** The architecture is built against the recognized standards for handling personal data in cloud systems, and the vendor handling identity documents is independently certified against several of them. Voxivium's own audits have not been done yet. When they are, the results go on the security page. We would rather tell you that than let you assume otherwise.

## The reason any of this matters

There is a version of civic technology that treats political opinion as an asset to be collected, packaged, and sold to whoever will pay. It is a real business model and it works.

Voxivium's position is that it is the wrong one for this particular product, because the value of the data depends entirely on people answering honestly, and nobody answers honestly into a system they suspect is watching them individually. The privacy architecture is not a feature bolted on for reassurance. It is the thing that makes the underlying measurement work at all.

If you want the specifics, including the standards involved and how to report a security problem, the [security page](/security) covers it.
