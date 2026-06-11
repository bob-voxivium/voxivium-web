/**
 * Firebase Web SDK client — single shared app + auth instance for any page
 * that needs voter / future-politician authentication off-mobile (e.g.,
 * /subscribe). The Voxivium backend's session-exchange endpoint
 * (`POST /auth/session`) is the source of truth for entitlement; Firebase
 * Auth just produces the ID token we hand to that endpoint.
 *
 * See features.md §2.6.1, voxivium-web/CLAUDE.md §5 Phase 3.
 *
 * Lazy initialization so pages that don't need auth (the marketing pages)
 * don't pull the SDK into their bundle.
 */
import { initializeApp, getApps, type FirebaseApp } from 'firebase/app'
import {
  browserLocalPersistence,
  getAuth,
  onAuthStateChanged,
  sendPasswordResetEmail as fbSendPasswordResetEmail,
  setPersistence,
  signInWithEmailAndPassword as fbSignInWithEmailAndPassword,
  signOut as fbSignOut,
  type Auth,
  type User,
} from 'firebase/auth'

let cachedApp: FirebaseApp | null = null
let cachedAuth: Auth | null = null
let persistenceConfigured = false

function firebaseConfig() {
  return {
    apiKey: import.meta.env.PUBLIC_FIREBASE_API_KEY,
    authDomain: import.meta.env.PUBLIC_FIREBASE_AUTH_DOMAIN,
    projectId: import.meta.env.PUBLIC_FIREBASE_PROJECT_ID,
    appId: import.meta.env.PUBLIC_FIREBASE_APP_ID,
  }
}

/**
 * Initialize (or retrieve) the singleton Firebase app + auth instance for
 * this browser session. Throws if any of the required env vars are missing
 * — callers should surface a "configuration error" state rather than
 * silently proceeding.
 */
export function getFirebaseAuth(): Auth {
  if (cachedAuth) return cachedAuth
  const config = firebaseConfig()
  for (const [key, value] of Object.entries(config)) {
    if (!value || value === 'TODO') {
      throw new Error(`Firebase config missing: ${key}. Set PUBLIC_FIREBASE_* in .env.`)
    }
  }
  cachedApp = getApps()[0] ?? initializeApp(config)
  cachedAuth = getAuth(cachedApp)
  // Persist sign-in across page navigations within voxivium.com so the
  // PayPal flow can read the current user after a redirect bounce.
  // Errors from setPersistence are non-fatal — the auth instance is still
  // usable, just with session-scoped persistence.
  if (!persistenceConfigured) {
    persistenceConfigured = true
    void setPersistence(cachedAuth, browserLocalPersistence).catch(() => {
      /* no-op; default persistence still works */
    })
  }
  return cachedAuth
}

export async function signIn(email: string, password: string): Promise<User> {
  const auth = getFirebaseAuth()
  const credential = await fbSignInWithEmailAndPassword(auth, email, password)
  return credential.user
}

export async function signOut(): Promise<void> {
  const auth = getFirebaseAuth()
  await fbSignOut(auth)
}

export async function sendPasswordResetEmail(email: string): Promise<void> {
  const auth = getFirebaseAuth()
  await fbSendPasswordResetEmail(auth, email)
}

/**
 * Subscribe to auth state changes. Returns an unsubscribe function. Use this
 * in page scripts to render the sign-in form vs. the subscribe content
 * reactively without polling.
 */
export function onAuthChanged(callback: (user: User | null) => void): () => void {
  const auth = getFirebaseAuth()
  return onAuthStateChanged(auth, callback)
}

/**
 * Get the current user's Firebase ID token, suitable for the Authorization
 * header on a call to the Voxivium backend. forceRefresh=true forces a
 * fresh token (use after a known revocation event).
 */
export async function getIdToken(forceRefresh = false): Promise<string | null> {
  const auth = getFirebaseAuth()
  const user = auth.currentUser
  if (!user) return null
  return user.getIdToken(forceRefresh)
}
