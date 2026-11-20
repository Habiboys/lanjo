package com.habiboys.lanjo

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import java.util.UUID

class LanjoNotificationListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val pkg = sbn.packageName ?: return
        if (pkg == packageName) return

        val prefs = getSharedPreferences(
            LanjoWidgetProvider.PREFS_NAME,
            Context.MODE_PRIVATE
        )
        if (!prefs.getBoolean("auto_detect_enabled", true)) return

        val extras = sbn.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim() ?: ""
        val body = if (bigText.length > text.length) bigText else text
        if (title.isEmpty() && body.isEmpty()) return

        parseAndEnqueue(
            context = this,
            packageName = pkg,
            title = title,
            body = body,
            requireKnownAppOrKeyword = true
        )
    }

    companion object {
        private val KNOWN_APPS = mapOf(
            "com.bca" to "BCA mobile",
            "com.bca.mybca.omni.android" to "myBCA",
            "id.bmri.livin" to "Livin' Mandiri",
            "id.co.bri.brimo" to "BRImo",
            "src.com.bni" to "BNI Mobile",
            "id.bni.wondr" to "wondr BNI",
            "com.jago.digitalBanking" to "Bank Jago",
            "id.co.bankbkemobile.digitalbank" to "SeaBank",
            "com.bcadigital.blu" to "blu BCA",
            "com.gojek.app" to "GoPay",
            "com.gojek.gopay" to "GoPay",
            "id.dana" to "DANA",
            "ovo.id" to "OVO",
            "com.shopee.id" to "ShopeePay",
            "com.telkom.mwallet" to "LinkAja"
        )

        private val RUPIAH_REGEX = Regex(
            """(?:Rp\.?|IDR)\s*([0-9]{1,3}(?:[.,][0-9]{3})+(?:[.,][0-9]{1,2})?|[0-9]{4,12})""",
            RegexOption.IGNORE_CASE
        )

        private val INCOME_KEYWORDS = listOf(
            "diterima", "uang masuk", "transfer masuk", "kredit", "top up berhasil",
            "menerima", "refund", "cashback diterima", "gaji"
        )

        private val EXPENSE_KEYWORDS = listOf(
            "pembayaran", "berhasil", "qris", "transfer ke", "debit",
            "bayar", "pembelian", "transaksi", "terkirim"
        )

        fun parseAndEnqueue(
            context: Context,
            packageName: String,
            title: String,
            body: String,
            requireKnownAppOrKeyword: Boolean = false
        ): JSONObject? {
            val combined = "$title $body".trim()
            val lower = combined.lowercase(Locale.ROOT)
            val knownAppName = KNOWN_APPS[packageName]

            val hasFinancialCue = knownAppName != null ||
                INCOME_KEYWORDS.any { lower.contains(it) } ||
                EXPENSE_KEYWORDS.any { lower.contains(it) }
            if (requireKnownAppOrKeyword && !hasFinancialCue) return null

            val match = RUPIAH_REGEX.find(combined) ?: return null
            val rawNum = match.groupValues[1]
            val amount = parseRupiahDigits(rawNum)
            if (amount <= 0) return null

            val isIncome = INCOME_KEYWORDS.any { lower.contains(it) }
            val type = if (isIncome) "income" else "expense"
            val appLabel = knownAppName ?: inferSourceLabel(combined, packageName)

            val prefs = context.getSharedPreferences(
                LanjoWidgetProvider.PREFS_NAME,
                Context.MODE_PRIVATE
            )
            val now = System.currentTimeMillis()
            val sig = "$appLabel|$type|$amount|${combined.take(48)}"
            val lastSig = prefs.getString("last_notif_sig", "")
            val lastTs = prefs.getLong("last_notif_ts", 0L)
            if (sig == lastSig && (now - lastTs) < 15_000L) {
                return null
            }

            val item = JSONObject().apply {
                put("id", UUID.randomUUID().toString())
                put("sourceApp", appLabel)
                put("packageName", packageName)
                put("title", title.ifEmpty { "Transaksi $appLabel" })
                put("body", body)
                put("amount", amount)
                put("type", type)
                put("detectedAtMs", now)
            }

            val existingRaw = prefs.getString("smart_inbox_queue", "[]") ?: "[]"
            val arr = try {
                JSONArray(existingRaw)
            } catch (_: Exception) {
                JSONArray()
            }

            val nextArr = JSONArray()
            nextArr.put(item)
            val maxItems = 40
            for (i in 0 until minOf(arr.length(), maxItems - 1)) {
                nextArr.put(arr.getJSONObject(i))
            }

            prefs.edit()
                .putString("smart_inbox_queue", nextArr.toString())
                .putString("last_notif_sig", sig)
                .putLong("last_notif_ts", now)
                .apply()

            MainActivity.notifySmartInboxUpdated()
            return item
        }

        private fun parseRupiahDigits(raw: String): Int {
            var cleaned = raw.trim()
            if (cleaned.length >= 3) {
                val tailSep = cleaned[cleaned.length - 3]
                if ((tailSep == ',' || tailSep == '.') &&
                    cleaned.substring(cleaned.length - 2).all { it.isDigit() }
                ) {
                    cleaned = cleaned.substring(0, cleaned.length - 3)
                }
            }
            val digitsOnly = cleaned.filter { it.isDigit() }
            return digitsOnly.toLongOrNull()?.coerceAtMost(2_000_000_000L)?.toInt() ?: 0
        }

        private fun inferSourceLabel(text: String, pkg: String): String {
            val l = text.lowercase(Locale.ROOT)
            return when {
                l.contains("qris") -> "QRIS"
                l.contains("bca") -> "BCA"
                l.contains("mandiri") || l.contains("livin") -> "Livin' Mandiri"
                l.contains("bri") || l.contains("brimo") -> "BRImo"
                l.contains("bni") || l.contains("wondr") -> "BNI"
                l.contains("gopay") -> "GoPay"
                l.contains("dana") -> "DANA"
                l.contains("ovo") -> "OVO"
                l.contains("shopee") -> "ShopeePay"
                l.contains("jago") -> "Bank Jago"
                l.contains("seabank") -> "SeaBank"
                pkg.contains(".") -> pkg.substringAfterLast('.').replaceFirstChar {
                    it.titlecase(Locale.ROOT)
                }
                else -> "Notifikasi Bank"
            }
        }
    }
}
