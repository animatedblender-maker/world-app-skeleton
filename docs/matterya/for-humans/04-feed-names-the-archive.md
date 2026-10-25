# Feed names: “Everything became The Archive”

### What you saw
On the feed, Sparks and Hubs cards all showed the account name **The Archive**. That felt broken — and it was.

### What you wanted (product rule)
| Content | Name on the card |
|---|---|
| **Spark uploaded by a user** | That person’s name |
| **Hub video shared to the feed** | The **person who shared** it, plus a line like **“Shared from Dokumentar AL”** or **“Shared from The Archive”** |
| **True Internet Archive seed** (catalog) | Channel **The Archive** |

Channels like **Dokumentar AL**, **Doku Deutschland**, etc. keep their real names.  
**The Archive** is only for the Internet Archive seed channel.

### Why it broke (plain)
The app stamped almost every Hubs post with a flag meaning “hub.”  
An older rule said: “if hub flag → this is an Archive seed → show The Archive.”  
So live channels and people got rewritten to The Archive.

The database still had the correct names. The **phone app** was overwriting them on screen.

### What we fixed
Code on branch `ios-native` now only treats **true Archive seeds** as The Archive.  
Live people and channels keep their names. Share cards keep “Shared from …”.

### What you need to do
1. **Rebuild / reinstall the iOS app** from the latest `ios-native` (this fix is client-side).  
2. Open Home / Sparks / Hubs and spot-check a few cards.  
3. You should see real people and real channel names again.

### Still confused?
Ask: “Is this an Internet Archive seed, or a live Matterya post?”  
Only seeds should say **The Archive** as the main account name.
