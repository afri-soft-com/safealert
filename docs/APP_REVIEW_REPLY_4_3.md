# Reply to App Review — Guidelines 4.3 / 4.2.6 (SafeAlert)

Paste into **App Store Connect → Reply to App Review** (English preferred by Apple).

---

Hello App Review team,

Thank you for the feedback. SafeAlert is **not** a template or white-label product. It is an original citizen-safety application built and operated by **AfriSoft** for communities in the Democratic Republic of Congo (starting with Kinshasa). Below are answers to your questions.

### 1. Functionality — what the app does and the problem it solves
SafeAlert lets a person in danger send a **SOS with live GPS** to their **trusted contacts** (SMS + push), optionally notify **neighborhood groups**, and view / report **community incidents on a map**. It also supports **secured trips** (ETA + delay alerts), **arrival timers (“I’m home”)**, a **discreet mode**, and optional **family live circles**. It does **not** replace official emergency services (police / ambulance); it fills the gap when users need to alert trusted people and share location quickly when those services are slow or unavailable.

### 2. Target audience
Primary users are **urban residents and families in DRC** (French-speaking), especially people who walk or travel in neighborhoods with security concerns. Secondary users include **community leaders / ops** who mediate incidents, and **B2B partners** (NGOs, security desks) via an API portal — not a consumer clone of a generic “tracker” app.

### 3. Market need not met by existing apps
Most global SOS apps assume reliable cellular data, Western emergency numbers, and English-first UX. SafeAlert is built for **local phone OTP (+243)**, **SMS fallback** for contacts without the app, **offline queues**, **French-first** (plus LN / SW / EN), and **community incident mapping** tied to Kinshasa neighborhoods — not a generic personal GPS tracker.

### 4. Beta testing and feedback applied
We ran **internal / closed testing** on Android (Play internal track) and iOS TestFlight with DRC testers. Feedback led to: OTP + local PIN (fewer SMS on reopen), CGU acceptance on login, clearer SOS hold UX, neighborhood digests in Africa/Kinshasa timezone, and removal of redundant legal buttons on the login screen (links remain in the required checkbox; the user manual is available after login).

### 5. Standalone vs suite
SafeAlert is a **standalone consumer product**. The companion **admin web console** and partner portal are operator tools for the same product, not separate App Store apps.

### 6. Could this be an IAP / expansion of another app?
No. We do not have another App Store app that already provides this SOS + community map experience. Premium features (if any) are optional expansions **inside** SafeAlert, not a separate app.

### 7. Shared binary / assets with other apps on our account
The SafeAlert **iOS binary is dedicated** to bundle id `com.kakiranya.safealert`. We do not ship multiple near-identical App Store apps from the same codebase under different brands.

### 8. Shared codebase / SDK with third parties beyond standard frameworks
We use standard SDKs only (Flutter, Firebase Messaging/Crashlytics, Google / Apple Sign-In, maps). There is **no commercial app-generator or white-label template SDK**. Custom backend APIs (SOS, trips, neighborhoods, partners) are owned and operated by AfriSoft.

### 9. Guideline 4.2.6 — client / template?
SafeAlert was **not** created via an app generation service and is **not** submitted on behalf of a third-party client as a templated clone. AfriSoft is the **content and service provider**: we operate the API, SMS OTP, maps data flows, and support. The app is submitted under our developer account because we own and run the service.

We have uploaded an updated build with a clearer login flow and refreshed product screenshots that reflect the real SafeAlert experience for Kinshasa users. Please re-review at your convenience.

Best regards,  
Celestin Kasereka — AfriSoft / SafeAlert  
Bundle ID: `com.kakiranya.safealert`
