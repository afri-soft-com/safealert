# Reply to App Review — Guideline 2.1 (law enforcement partnership)

Rejection of 2026-11-17, submission `826361d0-7a10-44c9-80d2-8b8a966d05c3`, build 1.0 (48).

Apple's request: "provide documentation or evidence of your relationship with local law
enforcement wherever the app is distributed", because the app "allows users to report
criminal activity".

AfriSoft has no police partnership, so we removed the crime report types from the iOS
app instead (see `reportableIncidentTypes` in `frontend/lib/data/incident_types.dart`):

- The iOS report form and map filter no longer offer "Agression", "Vol" and
  "Présence suspecte". The remaining types are Accident, Incendie and Autre.
  Android is unchanged.
- The report form shows: "SafeAlert ne le transmet pas à la police. En cas d'urgence,
  appelez les numéros officiels (onglet Urgences)."
- Two safety tips that said "signalez via l'app" now say to call official services and
  warn neighbours/relatives.

Before replying: select the new build in iOS App 1.0, then send the reply below and click
**Resubmit to App Review**.

---

Hello App Review team,

Thank you for your review. We do not have a partnership with law enforcement, so we
changed the app so that it can no longer be used to report criminal activity.

SafeAlert is a personal and community safety app, distributed only in the Democratic
Republic of the Congo. It does not send anything to the police and does not claim to:

- The SOS feature sends the user's location to the trusted contacts they chose
  (family, friends), by push notification and SMS.
- The community map lets residents warn their neighbours about safety hazards such as
  road accidents and fires. These notes are not passed to the police.
- The app lists the official emergency numbers and tells users to call them in an
  emergency.

In the new build we made these changes:

1. We removed the report categories that could be read as criminal reports
   ("Assault", "Theft", "Suspicious person"). Users can only report accidents, fires
   and other hazards.
2. The report form now states clearly that SafeAlert does not send reports to the
   police, and that users should call the official emergency numbers in an emergency.
3. We reworded the safety tips that mentioned reporting through the app.

We hope this answers your question. Please let us know if you need anything else.

Best regards,
Celestin Kasereka — AfriSoft / SafeAlert
