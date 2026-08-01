/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

#pragma once

#include <QtCore/QByteArray>
#include <QtCore/QList>
#include <QtCore/QLoggingCategory>
#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtNetwork/QAbstractSocket>

Q_DECLARE_LOGGING_CATEGORY(NtripTcpClientLog)

class QTcpSocket;

/// Async NTRIP client. Connects to an NTRIP caster over TCP, performs the
/// NTRIP handshake and emits complete, CRC validated RTCM 3.x frames.
class NtripTcpClient : public QObject
{
    Q_OBJECT

public:
    explicit NtripTcpClient(QObject *parent = nullptr);
    ~NtripTcpClient();

    void connectToCaster(const QString &hostAddress, quint16 port, const QString &username, const QString &password, const QString &mountpoint);
    void disconnectFromCaster();
    bool isConnected() const { return _state == State::Streaming; }

    /// Sends an NMEA sentence (GGA) to the caster. A trailing CRLF is added if missing.
    void sendNMEA(const QByteArray &sentence);

    /// Comma separated RTCM message id whitelist. Empty forwards all messages.
    void setWhitelist(const QString &whitelist);

signals:
    void connected();
    void disconnected();
    void errorOccurred(const QString &message);
    void rtcmDataReceived(QByteArrayView frame);

private slots:
    void _onSocketConnected();
    void _onSocketDisconnected();
    void _onSocketError(QAbstractSocket::SocketError socketError);
    void _onReadyRead();

private:
    enum class State {
        Idle,
        Connecting,
        WaitingForResponse,
        Streaming
    };

    void _sendRequest();
    void _handleResponse();
    void _parseStream();
    static bool _crc24qOk(const QByteArray &frame);
    void _fail(const QString &message);

    QTcpSocket *_socket = nullptr;
    State _state = State::Idle;
    QString _hostAddress;
    quint16 _port = 0;
    QString _username;
    QString _password;
    QString _mountpoint;
    QByteArray _buffer;
    QList<uint16_t> _whitelist;

    static constexpr uint8_t kRtcm3Preamble = 0xD3;
    static constexpr qsizetype kMaxResponseSize = 16 * 1024;
};
