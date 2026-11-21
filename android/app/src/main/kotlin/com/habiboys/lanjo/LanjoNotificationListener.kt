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
        if (sbn.isOngoing) return

        val notification = sbn.notification ?: return
        if ((notification.flags and Notification.FLAG_GROUP_SUMMARY) != 0) return

        val prefs = getSharedPreferences(
            LanjoWidgetProvider.PREFS_NAME,
            Context.MODE_PRIVATE
        )
        if (!prefs.getBoolean("auto_detect_enabled", true)) return

        val extras = notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim() ?: ""
        val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            ?.joinToString(" ") { it.toString().trim() }
            ?.trim()
            ?: ""
        val body = listOf(bigText, text, lines).maxByOrNull { it.length } ?: ""
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
        internal val KNOWN_APPS = mapOf(
            "com.bca" to "BCA mobile",
            "com.bca.mybca.omni.android" to "myBCA",
            "id.bmri.livin" to "Livin' Mandiri",
            "com.bankmandiri.mandirionline" to "Livin' Mandiri",
            "com.mandiri.livin" to "Livin' Mandiri",
            "id.co.bri.brimo" to "BRImo",
            "id.co.bri.brimo.android" to "BRImo",
            "src.com.bni" to "BNI Mobile",
            "id.bni.wondr" to "wondr BNI",
            "com.jago.digitalBanking" to "Bank Jago",
            "id.co.bankbkemobile.digitalbank" to "SeaBank",
            "com.bcadigital.blu" to "blu BCA",
            "com.btpn.dc" to "Jenius",
            "id.co.cimbniaga.mobile.android" to "OCTO Mobile",
            "com.cimb.octomobile" to "OCTO Mobile",
            "com.bsm.activity2" to "BSI Mobile",
            "com.bankbsi.byond" to "BYOND BSI",
            "net.myinfosys.PermataMobileX" to "PermataME",
            "com.bnc.finance" to "neobank",
            "id.co.hanabank.linebank" to "LINE Bank",
            "id.co.bankraya.raya" to "Bank Raya",
            "com.gojek.app" to "GoPay",
            "com.gojek.gopay" to "GoPay",
            "com.gopay.app" to "GoPay",
            "id.dana" to "DANA",
            "ovo.id" to "OVO",
            "com.shopee.id" to "ShopeePay",
            "com.shopeepay.id" to "ShopeePay",
            "com.telkom.mwallet" to "LinkAja"
        )

        private val RUPIAH_REGEX = Regex(
            """(?:Rp\.?|IDR)\s*([0-9]{1,3}(?:[.,][0-9]{3})+(?:[.,][0-9]{1,2})?|[0-9]{3,12})""",
            RegexOption.IGNORE_CASE
        )

        private val PROMO_OR_NON_TX_KEYWORDS = listOf(
            "promo", "nikmati harga", "nikmati promo", "nikmati diskon",
            "nikmati cashback", "nikmati gratis", "harga spesial", "spesial buat",
            "khusus buat", "makin hemat", "hemat hingga", "hemat s.d",
            "dapatkan cashback", "dapetin cashback", "voucher", "kupon", "diskon",
            "mulai dari", "klaim", "kesempatan", "penawaran", "flash sale",
            "undian", "serbu", "undang teman", "gratis ongkir",
            "jangan lewatkan", "cashback s.d", "cashback hingga",
            "kode otp", "kode verifikasi", "jangan berikan",
            "kode rahasia", "bersifat rahasia"
        )

        private val INCOME_KEYWORDS = listOf(
            "diterima", "uang masuk", "transfer masuk", "dana masuk", "pemasukan",
            "kredit", "top up berhasil", "menerima", "refund", "gaji"
        )

        private val EXPENSE_KEYWORDS = listOf(
            "pembayaran", "berhasil", "sukses", "qris", "transfer ke", "debit",
            "bayar", "pembelian", "transaksi", "terkirim", "mutasi", "potongan",
            "belanja", "tagihan", "tarik"
        )

        private val SOURCE_PATTERNS = listOf(
            Regex("""\bjago\b""") to "Bank Jago",
            Regex("""brimo|\bbri\b""") to "BRImo",
            Regex("""mybca|\bbca\b""") to "BCA mobile",
            Regex("""livin|mandiri""") to "Livin' Mandiri",
            Regex("""wondr|\bbni\b""") to "wondr BNI",
            Regex("""gopay""") to "GoPay",
            Regex("""\bdana\b""") to "DANA",
            Regex("""\bovo\b""") to "OVO",
            Regex("""shopee""") to "ShopeePay",
            Regex("""seabank""") to "SeaBank",
            Regex("""jenius""") to "Jenius",
            Regex("""byond|\bbsi\b""") to "BSI Mobile",
            Regex("""octo|cimb""") to "OCTO Mobile",
            Regex("""permata""") to "PermataME",
            Regex("""neobank|\bbnc\b""") to "neobank",
            Regex("""linkaja""") to "LinkAja",
            Regex("""\bblu\b""") to "blu BCA",
            Regex("""\bqris\b""") to "QRIS"
        )

        internal fun isPromoOrNonTransaction(text: String): Boolean {
            val lower = text.lowercase(Locale.ROOT)
            return PROMO_OR_NON_TX_KEYWORDS.any { lower.contains(it) }
        }

        fun parseAndEnqueue(
            context: Context,
            packageName: String,
            title: String,
            body: String,
            requireKnownAppOrKeyword: Boolean = false
        ): JSONObject? {
            val knownAppName = KNOWN_APPS[packageName]
            if (requireKnownAppOrKeyword && knownAppName == null) return null

            val combined = "$title $body".trim()
            if (isPromoOrNonTransaction(combined)) return null

            val lower = combined.lowercase(Locale.ROOT)
            val isSettledCashback = lower.contains("cashback") &&
                (lower.contains("masuk") ||
                    lower.contains("diterima") ||
                    lower.contains("berhasil"))
            val isIncome = isSettledCashback ||
                INCOME_KEYWORDS.any { lower.contains(it) }
            val hasFinancialCue = isIncome ||
                EXPENSE_KEYWORDS.any { lower.contains(it) }
            if (!hasFinancialCue) return null

            val match = RUPIAH_REGEX.find(combined) ?: return null
            val rawNum = match.groupValues[1]
            val amount = parseRupiahDigits(rawNum)
            if (amount <= 0) return null

            val type = if (isIncome) "income" else "expense"
            val appLabel = knownAppName ?: inferSourceLabel(title, body, packageName)

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

        private fun inferSourceLabel(title: String, body: String, pkg: String): String {
            val titleLower = title.lowercase(Locale.ROOT)
            for ((pattern, label) in SOURCE_PATTERNS) {
                if (pattern.containsMatchIn(titleLower)) return label
            }
            val bodyLower = body.lowercase(Locale.ROOT)
            for ((pattern, label) in SOURCE_PATTERNS) {
                if (pattern.containsMatchIn(bodyLower)) return label
            }
            return when {
                pkg.isNotEmpty() && pkg != "clipboard" && pkg != "share" && pkg.contains(".") ->
                    pkg.substringAfterLast('.').replaceFirstChar {
                        it.titlecase(Locale.ROOT)
                    }
                else -> "Notifikasi Bank"
            }
        }
    }
}
