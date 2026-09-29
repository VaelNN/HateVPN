package com.leadaxe.lxbox.vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import com.leadaxe.lxbox.R

class ServiceNotification(private val service: Service) {
    companion object {

        private const val CHANNEL_ID = "boxvpn_vpn_channel"
        private const val NOTIFICATION_ID = 1


        private const val ALERT_NOTIFICATION_ID = 2




        fun createChannel(ctx: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    L10n.str(ctx, R.string.notification_channel_name),
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description =
                        L10n.str(ctx, R.string.notification_channel_description)
                    setShowBadge(false)
                }
                BoxApplication.notificationManager.createNotificationChannel(channel)
            }
        }
















        fun isStalePresent(): Boolean = runCatching {
            BoxApplication.notificationManager.activeNotifications.any { it.id == NOTIFICATION_ID }
        }.getOrDefault(false)





        fun showAlert(ctx: Context, title: String, text: String) {
            createChannel(ctx)
            val openIntent = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            val builder = NotificationCompat.Builder(ctx, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_lock_lock)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                .setAutoCancel(true)
            if (openIntent != null) {
                builder.setContentIntent(
                    PendingIntent.getActivity(
                        ctx, 0, openIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                )
            }
            runCatching {
                (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                    .notify(ALERT_NOTIFICATION_ID, builder.build())
            }
        }
    }

    init {
        createChannel(service)
    }








    private fun buildNotification(title: String, text: String)
        : android.app.Notification {
        val openIntent = service.packageManager
            .getLaunchIntentForPackage(service.packageName)
        val pendingIntent = if (openIntent != null) {
            PendingIntent.getActivity(
                service, 0, openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else null

        val builder = NotificationCompat.Builder(service, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle(title)
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)

        if (pendingIntent != null) builder.setContentIntent(pendingIntent)




        builder
            .addAction(
                0,
                L10n.str(service, R.string.notification_action_stop),
                broadcastPI(BoxVpnService.ACTION_STOP, 1),
            )
            .addAction(
                0,
                L10n.str(service, R.string.notification_action_reconnect),
                broadcastPI(BoxVpnService.ACTION_RECONNECT, 2),
            )
        return builder.build()
    }




    private fun broadcastPI(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(action).setPackage(service.packageName)
        return PendingIntent.getBroadcast(
            service, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun show(title: String, text: String) {
        val notification = buildNotification(title, text)




        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            service.startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            service.startForeground(NOTIFICATION_ID, notification)
        }
    }

    fun showAlert(title: String, text: String) = showAlert(service, title, text)

    fun stop() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            service.stopForeground(Service.STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            service.stopForeground(true)
        }
    }
}
