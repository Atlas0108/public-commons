#!/usr/bin/env node
/**
 * Seeds Public Commons with demo data:
 *   - 5 demo users (Firebase Auth + `users` docs): 3 personal, 1 nonprofit, 1 business
 *   - 3 groups (2 public, 1 private) with various members
 *   - User connections: several users connected to each other
 *   - 3 community-event posts, 3 help-offer posts, 3 help-request posts
 *   - Comments from users on various posts
 *
 * Events use the same `posts` collection as offers/requests with kind `community_event` (see lib/core/models/post.dart).
 *
 *   If GOOGLE_APPLICATION_CREDENTIALS is unset, the script uses repo secrets/firebase-adminsdk.json
 *   when that file exists (gitignored). Otherwise set the env var to your service account JSON path.
 *   optional: export DEMO_SEED_PASSWORD="YourSharedPassword123!"
 *   cd scripts/seed_demo && npm install
 *   node seed_demo.mjs              # dry-run
 *   node seed_demo.mjs --execute    # write data
 *
 * Re-running with --execute creates additional posts/groups/comments (new IDs). Auth users are reused if the
 * emails already exist. Connections are idempotent (same doc IDs based on user pairs).
 * Optional: FIREBASE_STORAGE_BUCKET (default ${projectId}.firebasestorage.app).
 */

import admin from 'firebase-admin';
import ngeohash from 'ngeohash';
import { randomUUID } from 'node:crypto';

import {
  applyDefaultGoogleApplicationCredentialsIfUnset,
  assertValidGoogleApplicationCredentialsPath,
  resolveFirebaseProjectId,
} from '../resolve_firebase_project.mjs';

const execute = process.argv.includes('--execute');
const wantHelp = process.argv.includes('--help') || process.argv.includes('-h');

if (wantHelp) {
  console.log(`
Usage: node seed_demo.mjs [--execute]

  (default)  Print what would be created.
  --execute  Create Auth users (if missing) and write Firestore documents.

Env:
  GOOGLE_APPLICATION_CREDENTIALS  (optional if secrets/firebase-adminsdk.json exists) service account JSON path
  GOOGLE_CLOUD_PROJECT / GCLOUD_PROJECT / FIREBASE_PROJECT_ID  (optional; else project_id in key or repo firebase.json)
  DEMO_SEED_PASSWORD                (optional) password for all demo accounts; default built-in demo password
`);
  process.exit(0);
}

const DEMO_PASSWORD =
  process.env.DEMO_SEED_PASSWORD || 'CommonsDemo2026!';

// Default seed target after project migration. Still overridable via:
// GOOGLE_CLOUD_PROJECT / GCLOUD_PROJECT / FIREBASE_PROJECT_ID
process.env.FIREBASE_PROJECT_ID ??= 'public-commons';

/** All seeded posts use this point (Portland, Oregon) so local feeds map to one metro. */
const SEED_POST_LAT = 45.5152;
const SEED_POST_LNG = -122.6784;

/** Match lib/core/geo/geo_utils.dart: precision 5 (~4.9 km cells). JS ngeohash uses lat, lng. */
function geohash5(lat, lng) {
  return ngeohash.encode(lat, lng, 5);
}

let db;
let auth;
let projectId = '(dry-run)';
let GeoPoint;
let Timestamp;

if (execute) {
  applyDefaultGoogleApplicationCredentialsIfUnset(import.meta.url);
  assertValidGoogleApplicationCredentialsPath();
  const resolvedProjectId = resolveFirebaseProjectId(import.meta.url);
  if (!admin.apps.length) {
    admin.initializeApp(resolvedProjectId ? { projectId: resolvedProjectId } : {});
  }
  db = admin.firestore();
  auth = admin.auth();
  projectId = admin.app().options.projectId || resolvedProjectId;
  if (!projectId) {
    console.error(
      'Could not determine Firebase project ID. Set GOOGLE_CLOUD_PROJECT, use a service account JSON with "project_id", or run from the repo so ../../firebase.json is found.',
    );
    process.exit(1);
  }
  GeoPoint = admin.firestore.GeoPoint;
  Timestamp = admin.firestore.Timestamp;
}

const demoUsers = [
  {
    email: 'commons-demo-maya@example.invalid',
    displayName: 'Maya Chen',
    neighborhood: 'Northside Neighbor',
    lat: 37.7765,
    lng: -122.4172,
  },
  {
    email: 'commons-demo-jordan@example.invalid',
    displayName: 'Jordan Reed',
    neighborhood: 'Mission Roots',
    lat: 37.7599,
    lng: -122.4148,
  },
  {
    email: 'commons-demo-sam@example.invalid',
    displayName: 'Sam Okonkwo',
    neighborhood: 'Bayview Block',
    lat: 37.7308,
    lng: -122.3834,
  },
  {
    email: 'commons-demo-social-good-fund@example.invalid',
    displayName: 'Social Good Fund',
    accountType: 'nonprofit',
    organizationName: 'Social Good Fund',
    neighborhood: 'Portland Metro',
    lat: 45.5152,
    lng: -122.6784,
  },
  {
    email: 'commons-demo-mazlo@example.invalid',
    displayName: 'Mazlo',
    accountType: 'business',
    businessName: 'Mazlo',
    neighborhood: 'Pearl District',
    lat: 45.5253,
    lng: -122.6844,
  },
];

/** organizerIndex / authorIndex: 0–2 personal demos, 3 = Social Good Fund (nonprofit), 4 = Mazlo (business). */
const demoEvents = [
  {
    title: 'Community garden workday',
    description:
      'Mulch paths, plant winter greens, and share tools. Gloves provided; bring a water bottle.',
    locationDescription: 'SE Portland community garden — meet at the tool shed',
    organizerIndex: 3,
    startsInDays: 3,
    durationHours: 3,
  },
  {
    title: 'Neighborhood potluck',
    description:
      'Bring a dish to share (label ingredients). Live music and kids’ craft table in the back.',
    locationDescription: 'Alberta Arts district — check the map pin for the cross street',
    organizerIndex: 4,
    startsInDays: 10,
    durationHours: 4,
  },
  {
    title: 'Snow shovel brigade signup',
    description:
      'We pair volunteers with neighbors who need walks cleared after storms. Sign up for your block.',
    locationDescription: 'Virtual kickoff + shared spreadsheet — link in event chat',
    organizerIndex: 2,
    startsInDays: 45,
    durationHours: 2,
  },
];

const demoOffers = [
  {
    authorIndex: 3,
    title: 'Grant-writing office hours (virtual)',
    body: 'Social Good Fund is offering two 30-minute slots this week for small neighborhood projects — questions on applications, budgets, or timelines welcome.',
  },
  {
    authorIndex: 4,
    title: 'Complimentary tastings — new spring menu',
    body: 'Mazlo is sampling our spring pastries and pour-over bar Saturday 9–12; stop by and say hi to the team.',
  },
  {
    authorIndex: 0,
    title: 'Free compost delivery',
    body: 'I have extra finished compost from my bins — happy to drop off a few buckets within 2 miles.',
  },
];

const demoRequests = [
  {
    authorIndex: 4,
    title: 'Borrow a folding table for weekend pop-up',
    body: 'Mazlo needs one sturdy 6-foot folding table Sat–Sun for a sidewalk tasting; will pick up and return clean.',
  },
  {
    authorIndex: 3,
    title: 'Volunteers for supply sorting day',
    body: 'Social Good Fund needs 4–6 people for a 3-hour sort at our warehouse — gloves and snacks provided.',
  },
  {
    authorIndex: 1,
    title: 'Help setting up a used laptop',
    body: 'Bought a refurbished Mac for my kid; would love 30 minutes with someone patient to get accounts and parental controls sorted.',
  },
];

const demoGroups = [
  {
    name: 'Portland Community Gardeners',
    description: 'A group for neighbors passionate about urban gardening, composting, and growing food together.',
    rules: 'Be respectful. Share tips freely. No commercial posts without approval.',
    visibility: 'public',
    ownerIndex: 0,
    memberIndices: [0, 1, 2, 3],
  },
  {
    name: 'Pearl District Parents',
    description: 'Connect with other parents in the Pearl District. Playdates, school tips, family-friendly events.',
    rules: 'Keep it family-friendly. No solicitation. Support each other!',
    visibility: 'public',
    ownerIndex: 1,
    memberIndices: [1, 2, 4],
  },
  {
    name: 'Small Business Alliance',
    description: 'Local business owners supporting each other. Share resources, collaborate, and grow together.',
    rules: 'Business-focused discussion only. No spam. Cross-promotion encouraged with permission.',
    visibility: 'private',
    ownerIndex: 4,
    memberIndices: [3, 4],
  },
];

const demoConnections = [
  { userIndex: 0, peerIndex: 1 },
  { userIndex: 0, peerIndex: 2 },
  { userIndex: 1, peerIndex: 2 },
  { userIndex: 3, peerIndex: 4 },
  { userIndex: 2, peerIndex: 3 },
];

const demoComments = [
  {
    postType: 'event',
    postIndex: 0,
    authorIndex: 1,
    text: "Count me in! I'll bring extra gloves for anyone who needs them.",
  },
  {
    postType: 'event',
    postIndex: 0,
    authorIndex: 2,
    text: 'What time should we arrive? Is there parking nearby?',
  },
  {
    postType: 'event',
    postIndex: 1,
    authorIndex: 0,
    text: "Can't wait for this! I'm bringing my famous mac and cheese.",
  },
  {
    postType: 'offer',
    postIndex: 0,
    authorIndex: 1,
    text: "This is so helpful! We've been struggling with our grant application for months.",
  },
  {
    postType: 'offer',
    postIndex: 2,
    authorIndex: 2,
    text: 'Yes please! My raised beds could really use some compost. Can you deliver to Bayview?',
  },
  {
    postType: 'request',
    postIndex: 2,
    authorIndex: 0,
    text: "I can help with this! I set up my parents' computers all the time. DM me.",
  },
  {
    postType: 'request',
    postIndex: 1,
    authorIndex: 2,
    text: "I can come Saturday morning. What's the address?",
  },
];

async function getOrCreateUser({ email, password, displayName }) {
  try {
    const existing = await auth.getUserByEmail(email);
    return existing;
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    return auth.createUser({
      email,
      password,
      displayName,
      emailVerified: false,
    });
  }
}

async function seedUserDoc(uid, u) {
  const gp = new GeoPoint(u.lat, u.lng);
  const accountType = u.accountType || 'personal';
  const data = {
    displayName: u.displayName,
    accountType,
    discoveryRadiusMiles: 25,
    karma: 12,
    createdAt: Timestamp.now(),
    homeGeoPoint: gp,
    neighborhoodLabel: u.neighborhood,
    eventsAttended: 4,
    requestsFulfilled: 2,
  };
  const FieldValue = admin.firestore.FieldValue;
  if (accountType === 'nonprofit') {
    data.organizationName = u.organizationName || u.displayName;
    data.firstName = FieldValue.delete();
    data.lastName = FieldValue.delete();
    data.businessName = FieldValue.delete();
  } else if (accountType === 'business') {
    data.businessName = u.businessName || u.displayName;
    data.firstName = FieldValue.delete();
    data.lastName = FieldValue.delete();
    data.organizationName = FieldValue.delete();
  }
  await db.collection('users').doc(uid).set(data, { merge: true });
}

async function seedCommunityEventPost(template, usersByIndex) {
  const org = usersByIndex[template.organizerIndex];
  const id = randomUUID();
  if (!execute) return id;

  const starts = new Date();
  starts.setDate(starts.getDate() + template.startsInDays);
  starts.setHours(10, 0, 0, 0);
  const ends = new Date(starts.getTime() + template.durationHours * 60 * 60 * 1000);
  const gp = new GeoPoint(SEED_POST_LAT, SEED_POST_LNG);
  /** Matches CommonsPost.toCreateMap() for PostKind.communityEvent (lib/core/models/post.dart). */
  const data = {
    authorId: org.uid,
    authorName: org.displayName,
    kind: 'community_event',
    title: template.title,
    body: template.description,
    geoPoint: gp,
    geohash: geohash5(SEED_POST_LAT, SEED_POST_LNG),
    status: 'open',
    createdAt: Timestamp.now(),
    startsAt: Timestamp.fromDate(starts),
    endsAt: Timestamp.fromDate(ends),
    locationDescription: template.locationDescription,
  };
  await db.collection('posts').doc(id).set(data);
  return id;
}

/** @param {'help_offer' | 'help_request'} kind */
async function seedHelpDeskPost(template, usersByIndex, kind) {
  const author = usersByIndex[template.authorIndex];
  const id = randomUUID();
  if (!execute) return id;

  const gp = new GeoPoint(SEED_POST_LAT, SEED_POST_LNG);
  const data = {
    authorId: author.uid,
    authorName: author.displayName,
    kind,
    title: template.title,
    body: template.body,
    geoPoint: gp,
    geohash: geohash5(SEED_POST_LAT, SEED_POST_LNG),
    status: 'open',
    createdAt: Timestamp.now(),
  };
  await db.collection('posts').doc(id).set(data);
  return id;
}

async function seedGroup(template, usersByIndex) {
  const owner = usersByIndex[template.ownerIndex];
  const memberIds = template.memberIndices.map((i) => usersByIndex[i].uid);
  const id = randomUUID();
  if (!execute) return id;

  const data = {
    name: template.name,
    description: template.description,
    rules: template.rules,
    visibility: template.visibility,
    ownerId: owner.uid,
    memberIds,
    createdAt: Timestamp.now(),
  };
  await db.collection('groups').doc(id).set(data);
  return id;
}

async function seedConnection(user1, user2) {
  if (!execute) return;

  const batch = db.batch();
  const now = Timestamp.now();

  batch.set(db.collection('users').doc(user1.uid).collection('connections').doc(user2.uid), {
    peerId: user2.uid,
    peerDisplayName: user2.displayName,
    connectedAt: now,
  });

  batch.set(db.collection('users').doc(user2.uid).collection('connections').doc(user1.uid), {
    peerId: user1.uid,
    peerDisplayName: user1.displayName,
    connectedAt: now,
  });

  await batch.commit();
}

async function seedComment(postId, author, text) {
  const id = randomUUID();
  if (!execute) return id;

  const data = {
    postId,
    authorId: author.uid,
    authorName: author.displayName,
    text,
    createdAt: Timestamp.now(),
  };
  await db.collection('posts').doc(postId).collection('comments').doc(id).set(data);
  return id;
}

async function main() {
  if (!execute) {
    console.log('Dry run (no writes). Add --execute to seed.\n');
  }

  console.log(`Project: ${projectId}`);
  console.log(`Demo password (new users only): ${DEMO_PASSWORD}\n`);

  const usersByIndex = [];

  for (const u of demoUsers) {
    if (execute) {
      const rec = await getOrCreateUser({
        email: u.email,
        password: DEMO_PASSWORD,
        displayName: u.displayName,
      });
      await seedUserDoc(rec.uid, u);
      usersByIndex.push({
        uid: rec.uid,
        email: u.email,
        displayName: u.displayName,
        lat: u.lat,
        lng: u.lng,
      });
      console.log(`User: ${u.displayName} <${u.email}>  uid=${rec.uid}`);
    } else {
      usersByIndex.push({
        uid: '(dry-run)',
        email: u.email,
        displayName: u.displayName,
        lat: u.lat,
        lng: u.lng,
      });
      console.log(`User: ${u.displayName} <${u.email}>`);
    }
  }

  console.log('\n--- Groups ---');
  for (const g of demoGroups) {
    const id = await seedGroup(g, usersByIndex);
    const memberNames = g.memberIndices.map((i) => demoUsers[i].displayName).join(', ');
    console.log(`Group: "${g.name}" (${g.visibility}) → ${execute ? id : '(would create)'}`);
    console.log(`  Owner: ${demoUsers[g.ownerIndex].displayName}`);
    console.log(`  Members: ${memberNames}`);
  }

  console.log('\n--- Connections ---');
  for (const conn of demoConnections) {
    const user1 = usersByIndex[conn.userIndex];
    const user2 = usersByIndex[conn.peerIndex];
    await seedConnection(user1, user2);
    console.log(`Connected: ${user1.displayName} ↔ ${user2.displayName}`);
  }

  const postIdsByType = {
    event: [],
    offer: [],
    request: [],
  };

  console.log('\n--- Events ---');
  for (const ev of demoEvents) {
    const id = await seedCommunityEventPost(ev, usersByIndex);
    postIdsByType.event.push(id);
    console.log(`Event post: "${ev.title}" → ${execute ? id : '(would create)'}`);
  }

  console.log('\n--- Offers ---');
  for (const off of demoOffers) {
    const id = await seedHelpDeskPost(off, usersByIndex, 'help_offer');
    postIdsByType.offer.push(id);
    console.log(`Offer: "${off.title}" → ${execute ? id : '(would create)'}`);
  }

  console.log('\n--- Requests ---');
  for (const req of demoRequests) {
    const id = await seedHelpDeskPost(req, usersByIndex, 'help_request');
    postIdsByType.request.push(id);
    console.log(`Request: "${req.title}" → ${execute ? id : '(would create)'}`);
  }

  console.log('\n--- Comments ---');
  for (const c of demoComments) {
    const postId = postIdsByType[c.postType][c.postIndex];
    const author = usersByIndex[c.authorIndex];
    const id = await seedComment(postId, author, c.text);
    const truncatedText = c.text.length > 40 ? c.text.slice(0, 40) + '...' : c.text;
    console.log(`Comment by ${author.displayName}: "${truncatedText}" → ${execute ? id : '(would create)'}`);
  }

  if (execute) {
    console.log('\nSeed complete. Sign in with any demo email and the password above.');
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
