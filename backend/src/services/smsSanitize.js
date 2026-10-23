/**
 * SerdiPay / DreamDigital (via hub AfriSoft) often rejects:
 * - sentence punctuation (. : ; ! ?)
 * - WebOTP lines (@host #code) and hash `<#>`
 */
function sanitizeSmsPourSerdiPay(text) {
  if (!text || !String(text).trim()) return text;

  const lines = String(text)
    .replace(/\r\n/g, "\n")
    .split("\n")
    .map((l) => l.trim())
    .filter((line) => {
      if (!line) return false;
      if (line.startsWith("@")) return false;
      if (line.includes("@") && line.includes("#")) return false;
      if (line.startsWith("<#>")) return false;
      return true;
    });

  let joined = lines.join(" ");
  joined = joined.replace(/\.(\s|$)/g, " $1");
  joined = joined.replace(/[:;!?]/g, " ");
  joined = joined.replace(/[@#]/g, " ");
  joined = joined.replace(/\s+/g, " ").trim();

  if (!joined) {
    joined = String(text).replace(/[@#]/g, " ").replace(/\s+/g, " ").trim();
  }
  return joined;
}

module.exports = { sanitizeSmsPourSerdiPay };
