/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

#include "NtripTcpClient.h"
#include "QGCLoggingCategory.h"

#include <QtCore/QStringList>
#include <QtNetwork/QTcpSocket>

QGC_LOGGING_CATEGORY(NtripTcpClientLog, "qgc.gps.ntriptcpclient")

namespace {

struct Crc24qTable {
    uint32_t table[256];
    Crc24qTable()
    {
        for (uint32_t i = 0; i < 256; ++i) {
            uint32_t crc = i << 16;
            for (int j = 0; j < 8; ++j) {
                crc <<= 1;
                if (crc & 0x01000000U) {
                    crc ^= 0x01864CFBU;
                }
            }
            table[i] = crc;
        }
    }
};

} // namespace

NtripTcpClient::NtripTcpClient(QObject *parent)
    : QObject(parent)
    , _socket(new QTcpSocket(this))
{
    (void) connect(_socket, &QTcpSocket::connected, this, &NtripTcpClient::_onSocketConnected);
    (void) connect(_socket, &QTcpSocket::disconnected, this, &NtripTcpClient::_onSocketDisconnected);
    (void) connect(_socket, &QTcpSocket::errorOccurred, this, &NtripTcpClient::_onSocketError);
    (void) connect(_socket, &QTcpSocket::readyRead, this, &NtripTcpClient::_onReadyRead);
}

NtripTcpClient::~NtripTcpClient()
{
    disconnectFromCaster();
}

void NtripTcpClient::connectToCaster(const QString &hostAddress, quint16 port, const QString &username, const QString &password, const QString &mountpoint)
{
    disconnectFromCaster();

    _hostAddress = hostAddress;
    _port = port;
    _username = username;
    _password = password;
    _mountpoint = mountpoint;
    _buffer.clear();

    qCDebug(NtripTcpClientLog) << "Connecting to" << hostAddress << port << mountpoint;
    _state = State::Connecting;
    _socket->connectToHost(hostAddress, port);
}

void NtripTcpClient::disconnectFromCaster()
{
    if (_state == State::Idle) {
        return;
    }

    _state = State::Idle;
    _socket->disconnectFromHost();
    if (_socket->state() != QAbstractSocket::UnconnectedState) {
        _socket->abort();
    }
}

void NtripTcpClient::sendNMEA(const QByteArray &sentence)
{
    if ((_state != State::Streaming) || sentence.isEmpty()) {
        return;
    }

    QByteArray data = sentence;
    if (!data.endsWith("\r\n")) {
        data.append("\r\n");
    }
    (void) _socket->write(data);
}

void NtripTcpClient::setWhitelist(const QString &whitelist)
{
    _whitelist.clear();
    const QStringList parts = whitelist.split(QLatin1Char(','), Qt::SkipEmptyParts);
    for (const QString &part : parts) {
        bool ok = false;
        const uint16_t id = part.trimmed().toUShort(&ok);
        if (ok) {
            _whitelist.append(id);
        }
    }
}

void NtripTcpClient::_onSocketConnected()
{
    if (_state != State::Connecting) {
        return;
    }

    if (_mountpoint.isEmpty()) {
        // Raw RTCM over TCP, no NTRIP handshake required
        qCDebug(NtripTcpClientLog) << "Connected, streaming raw RTCM";
        _state = State::Streaming;
        emit connected();
        return;
    }

    _sendRequest();
    _state = State::WaitingForResponse;
}

void NtripTcpClient::_sendRequest()
{
    QByteArray request;
    request.append("GET /").append(_mountpoint.toUtf8()).append(" HTTP/1.1\r\n");
    request.append("Host: ").append(_hostAddress.toUtf8()).append(":").append(QByteArray::number(_port)).append("\r\n");
    request.append("Ntrip-Version: Ntrip/2.0\r\n");
    request.append("User-Agent: NTRIP QGroundControl\r\n");
    request.append("Accept: */*\r\n");
    request.append("Connection: close\r\n");
    if (!_username.isEmpty()) {
        const QByteArray auth = (_username + QLatin1Char(':') + _password).toUtf8().toBase64();
        request.append("Authorization: Basic ").append(auth).append("\r\n");
    }
    request.append("\r\n");

    qCDebug(NtripTcpClientLog) << "Sending NTRIP request for mountpoint" << _mountpoint;
    (void) _socket->write(request);
}

void NtripTcpClient::_onReadyRead()
{
    _buffer.append(_socket->readAll());

    if (_state == State::WaitingForResponse) {
        _handleResponse();
    }

    if (_state == State::Streaming) {
        _parseStream();
    }
}

void NtripTcpClient::_handleResponse()
{
    if (_buffer.size() > kMaxResponseSize) {
        _fail(QStringLiteral("Invalid response from caster"));
        return;
    }

    // NTRIP v1 casters reply with a single "ICY 200 OK" line
    if (_buffer.startsWith("ICY")) {
        const qsizetype lineEnd = _buffer.indexOf("\r\n");
        if (lineEnd < 0) {
            return;
        }
        const QByteArray statusLine = _buffer.left(lineEnd);
        _buffer.remove(0, lineEnd + 2);
        if (!statusLine.contains("200")) {
            _fail(QString::fromUtf8(statusLine));
            return;
        }
        qCDebug(NtripTcpClientLog) << "Caster responded:" << statusLine;
        _state = State::Streaming;
        emit connected();
        return;
    }

    // Mountpoint not available, caster sends the source table instead
    if (_buffer.startsWith("SOURCETABLE")) {
        _fail(QStringLiteral("Mountpoint not available on caster"));
        return;
    }

    // NTRIP v2 standard HTTP response
    if (_buffer.startsWith("HTTP")) {
        const qsizetype headerEnd = _buffer.indexOf("\r\n\r\n");
        if (headerEnd < 0) {
            return;
        }
        const QByteArray statusLine = _buffer.left(_buffer.indexOf("\r\n"));
        _buffer.remove(0, headerEnd + 4);
        if (!statusLine.contains("200")) {
            _fail(QString::fromUtf8(statusLine));
            return;
        }
        qCDebug(NtripTcpClientLog) << "Caster responded:" << statusLine;
        _state = State::Streaming;
        emit connected();
        return;
    }

    // Unknown response, wait for more data unless it clearly is an error
    if (_buffer.startsWith("ERROR")) {
        _fail(QString::fromUtf8(_buffer));
    }
}

void NtripTcpClient::_parseStream()
{
    while (true) {
        const qsizetype preambleIndex = _buffer.indexOf(static_cast<char>(kRtcm3Preamble));
        if (preambleIndex < 0) {
            _buffer.clear();
            return;
        }
        if (preambleIndex > 0) {
            _buffer.remove(0, preambleIndex);
        }
        if (_buffer.size() < 3) {
            return;
        }

        const uint16_t payloadLength = ((static_cast<uint8_t>(_buffer[1]) & 0x03U) << 8) | static_cast<uint8_t>(_buffer[2]);
        const qsizetype frameLength = 3 + payloadLength + 3;
        if (_buffer.size() < frameLength) {
            return;
        }

        const QByteArray frame = _buffer.left(frameLength);
        if (_crc24qOk(frame)) {
            const uint16_t messageId = (static_cast<uint8_t>(frame[3]) << 4) | (static_cast<uint8_t>(frame[4]) >> 4);
            if (_whitelist.isEmpty() || _whitelist.contains(messageId)) {
                emit rtcmDataReceived(frame);
            }
            _buffer.remove(0, frameLength);
        } else {
            qCWarning(NtripTcpClientLog) << "RTCM frame CRC mismatch, resyncing";
            _buffer.remove(0, 1);
        }
    }
}

bool NtripTcpClient::_crc24qOk(const QByteArray &frame)
{
    static const Crc24qTable crcTable;

    uint32_t crc = 0;
    const qsizetype length = frame.size() - 3;
    for (qsizetype i = 0; i < length; ++i) {
        crc = ((crc << 8) & 0x00FFFFFFU) ^ crcTable.table[((crc >> 16) ^ static_cast<uint8_t>(frame[i])) & 0xFFU];
    }

    const uint32_t frameCrc = (static_cast<uint32_t>(static_cast<uint8_t>(frame[length])) << 16)
                            | (static_cast<uint32_t>(static_cast<uint8_t>(frame[length + 1])) << 8)
                            | static_cast<uint8_t>(frame[length + 2]);
    return (crc == frameCrc);
}

void NtripTcpClient::_fail(const QString &message)
{
    qCWarning(NtripTcpClientLog) << "NTRIP connection failed:" << message;
    emit errorOccurred(message);
    disconnectFromCaster();
}

void NtripTcpClient::_onSocketDisconnected()
{
    if (_state != State::Idle) {
        qCDebug(NtripTcpClientLog) << "Disconnected from caster";
        _state = State::Idle;
        emit disconnected();
    }
}

void NtripTcpClient::_onSocketError(QAbstractSocket::SocketError socketError)
{
    Q_UNUSED(socketError);
    if (_state == State::Idle) {
        return;
    }

    emit errorOccurred(_socket->errorString());

    // Make sure a failed connection attempt always results in a disconnected()
    // signal so the manager can schedule a reconnect.
    if (_socket->state() == QAbstractSocket::UnconnectedState) {
        _state = State::Idle;
        emit disconnected();
    }
}
