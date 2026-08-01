/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

#include "NTRIPManager.h"
#include "MultiVehicleManager.h"
#include "NTRIPSettings.h"
#include "NtripTcpClient.h"
#include "PositionManager.h"
#include "QGCLoggingCategory.h"
#include "RTCMMavlink.h"
#include "SettingsManager.h"
#include "Vehicle.h"

#include <QtCore/QDateTime>
#include <QtPositioning/QGeoCoordinate>

QGC_LOGGING_CATEGORY(NTRIPManagerLog, "qgc.gps.ntripmanager")

NTRIPManager::NTRIPManager(QObject *parent)
    : QObject(parent)
    , _client(new NtripTcpClient(this))
    , _rtcmMavlink(new RTCMMavlink(this))
    , _ggaTimer(new QTimer(this))
    , _reconnectTimer(new QTimer(this))
{
    _ggaTimer->setInterval(kGGAIntervalMSecs);
    (void) connect(_ggaTimer, &QTimer::timeout, this, &NTRIPManager::_sendGGA);

    _reconnectTimer->setSingleShot(true);
    _reconnectTimer->setInterval(kReconnectIntervalMSecs);
    (void) connect(_reconnectTimer, &QTimer::timeout, this, &NTRIPManager::_start);

    (void) connect(_client, &NtripTcpClient::rtcmDataReceived, _rtcmMavlink, &RTCMMavlink::RTCMDataUpdate);
    (void) connect(_client, &NtripTcpClient::connected, this, &NTRIPManager::_onConnected);
    (void) connect(_client, &NtripTcpClient::disconnected, this, &NTRIPManager::_onDisconnected);
    (void) connect(_client, &NtripTcpClient::errorOccurred, this, &NTRIPManager::_onError);

    NTRIPSettings *const settings = SettingsManager::instance()->ntripSettings();
    (void) connect(settings->ntripServerConnectEnabled(), &Fact::rawValueChanged, this, &NTRIPManager::_onConnectEnabledChanged);
    (void) connect(settings->ntripServerHostAddress(), &Fact::rawValueChanged, this, &NTRIPManager::_onConnectionSettingsChanged);
    (void) connect(settings->ntripServerPort(), &Fact::rawValueChanged, this, &NTRIPManager::_onConnectionSettingsChanged);
    (void) connect(settings->ntripUsername(), &Fact::rawValueChanged, this, &NTRIPManager::_onConnectionSettingsChanged);
    (void) connect(settings->ntripPassword(), &Fact::rawValueChanged, this, &NTRIPManager::_onConnectionSettingsChanged);
    (void) connect(settings->ntripMountpoint(), &Fact::rawValueChanged, this, &NTRIPManager::_onConnectionSettingsChanged);
    (void) connect(settings->ntripWhitelist(), &Fact::rawValueChanged, this, &NTRIPManager::_onConnectionSettingsChanged);

    if (settings->ntripServerConnectEnabled()->rawValue().toBool()) {
        _start();
    } else {
        _setStatus(tr("Disconnected"));
    }
}

NTRIPManager::~NTRIPManager()
{
    _stop();
}

bool NTRIPManager::connected() const
{
    return _connected;
}

void NTRIPManager::_start()
{
    NTRIPSettings *const settings = SettingsManager::instance()->ntripSettings();
    if (!settings->ntripServerConnectEnabled()->rawValue().toBool()) {
        return;
    }

    const QString hostAddress = settings->ntripServerHostAddress()->rawValue().toString();
    if (hostAddress.isEmpty()) {
        _setStatus(tr("Error: No host address specified"));
        return;
    }

    _client->setWhitelist(settings->ntripWhitelist()->rawValue().toString());
    _setStatus(tr("Connecting to %1...").arg(hostAddress));

    _client->connectToCaster(
        hostAddress,
        static_cast<quint16>(settings->ntripServerPort()->rawValue().toInt()),
        settings->ntripUsername()->rawValue().toString(),
        settings->ntripPassword()->rawValue().toString(),
        settings->ntripMountpoint()->rawValue().toString()
    );
}

void NTRIPManager::_stop()
{
    _reconnectTimer->stop();
    _ggaTimer->stop();
    _client->disconnectFromCaster();
    _setConnected(false);
    _setStatus(tr("Disconnected"));
}

void NTRIPManager::_onConnectEnabledChanged()
{
    NTRIPSettings *const settings = SettingsManager::instance()->ntripSettings();
    if (settings->ntripServerConnectEnabled()->rawValue().toBool()) {
        _start();
    } else {
        _stop();
    }
}

void NTRIPManager::_onConnectionSettingsChanged()
{
    NTRIPSettings *const settings = SettingsManager::instance()->ntripSettings();
    if (!settings->ntripServerConnectEnabled()->rawValue().toBool()) {
        return;
    }

    // Restart the connection to pick up the new settings
    _client->disconnectFromCaster();
    _setConnected(false);
    _setStatus(tr("Reconnecting..."));
    _reconnectTimer->start();
}

void NTRIPManager::_onConnected()
{
    qCDebug(NTRIPManagerLog) << "NTRIP connected";
    _reconnectTimer->stop();
    _setConnected(true);
    _setStatus(tr("Connected, streaming RTCM"));
    _sendGGA();
    _ggaTimer->start();
}

void NTRIPManager::_onDisconnected()
{
    qCDebug(NTRIPManagerLog) << "NTRIP disconnected";
    _ggaTimer->stop();
    _setConnected(false);

    NTRIPSettings *const settings = SettingsManager::instance()->ntripSettings();
    if (settings->ntripServerConnectEnabled()->rawValue().toBool()) {
        _setStatus(tr("Disconnected, retrying..."));
        _reconnectTimer->start();
    } else {
        _setStatus(tr("Disconnected"));
    }
}

void NTRIPManager::_onError(const QString &message)
{
    qCWarning(NTRIPManagerLog) << "NTRIP error:" << message;
    _setStatus(tr("Error: %1").arg(message));
}

void NTRIPManager::_setStatus(const QString &status)
{
    if (_ntripStatus != status) {
        _ntripStatus = status;
        emit ntripStatusChanged();
    }
}

void NTRIPManager::_setConnected(bool connected)
{
    if (_connected != connected) {
        _connected = connected;
        emit connectedChanged();
    }
}

void NTRIPManager::_sendGGA()
{
    const QByteArray gga = _buildGGA();
    if (!gga.isEmpty()) {
        _client->sendNMEA(gga);
    }
}

QByteArray NTRIPManager::_buildGGA() const
{
    QGeoCoordinate coord;
    if (Vehicle *const vehicle = MultiVehicleManager::instance()->activeVehicle()) {
        coord = vehicle->coordinate();
    }
    if (!coord.isValid()) {
        coord = QGCPositionManager::instance()->gcsPosition();
    }
    if (!coord.isValid()) {
        return QByteArray();
    }

    double latitude = coord.latitude();
    const QChar latitudeDir = (latitude < 0.0) ? QChar('S') : QChar('N');
    latitude = qAbs(latitude);
    const int latitudeDegrees = static_cast<int>(latitude);
    const double latitudeMinutes = (latitude - latitudeDegrees) * 60.0;

    double longitude = coord.longitude();
    const QChar longitudeDir = (longitude < 0.0) ? QChar('W') : QChar('E');
    longitude = qAbs(longitude);
    const int longitudeDegrees = static_cast<int>(longitude);
    const double longitudeMinutes = (longitude - longitudeDegrees) * 60.0;

    double altitude = coord.altitude();
    if (qIsNaN(altitude)) {
        altitude = 0.0;
    }

    const QTime utcTime = QDateTime::currentDateTimeUtc().time();
    const QString sentence = QStringLiteral("GPGGA,%1,%2%3,%4,%5%6,%7,1,12,0.8,%8,M,0.0,M,,")
        .arg(utcTime.toString(QStringLiteral("hhmmss.zzz")).left(9))
        .arg(latitudeDegrees, 2, 10, QChar('0'))
        .arg(latitudeMinutes, 7, 'f', 4, QChar('0'))
        .arg(latitudeDir)
        .arg(longitudeDegrees, 3, 10, QChar('0'))
        .arg(longitudeMinutes, 7, 'f', 4, QChar('0'))
        .arg(longitudeDir)
        .arg(altitude, 0, 'f', 1);

    uint8_t checksum = 0;
    const QByteArray sentenceUtf8 = sentence.toUtf8();
    for (const char c : sentenceUtf8) {
        checksum ^= static_cast<uint8_t>(c);
    }

    return QByteArray("$").append(sentenceUtf8).append("*").append(QByteArray::number(checksum, 16).toUpper().rightJustified(2, '0'));
}
