package services

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

// Edge TTS：复用微软 Edge 浏览器「大声朗读」的免费在线语音服务，无需订阅密钥。
// 该端点为非官方接口，可能随时变更；调用失败时应有重试/降级。
const (
	edgeTrustedClientToken  = "6A5AA1D4EAFF4E9FB37E23D68491D6F4"
	edgeWSSBase             = "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1"
	edgeChromiumMajor       = "143"
	edgeChromiumFullVersion = "143.0.3650.75"
	edgeOutputFormat        = "audio-24khz-48kbitrate-mono-mp3"
	edgeOriginExtension     = "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold"
)

// synthesizeEdgeTTS 通过 Edge TTS WebSocket 合成语音，返回 MP3 字节。
func synthesizeEdgeTTS(ctx context.Context, text, voice, rate, pitch, volume string) ([]byte, error) {
	wssURL := fmt.Sprintf(
		"%s?TrustedClientToken=%s&Sec-MS-GEC=%s&Sec-MS-GEC-Version=1-%s&ConnectionId=%s",
		edgeWSSBase, edgeTrustedClientToken, edgeSecMSGEC(), edgeChromiumFullVersion, edgeHexID(),
	)

	header := http.Header{}
	header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/"+edgeChromiumMajor+".0.0.0 Safari/537.36 Edg/"+edgeChromiumMajor+".0.0.0")
	header.Set("Accept-Encoding", "gzip, deflate, br, zstd")
	header.Set("Accept-Language", "en-US,en;q=0.9")
	header.Set("Pragma", "no-cache")
	header.Set("Cache-Control", "no-cache")
	header.Set("Origin", edgeOriginExtension)

	dialer := websocket.Dialer{HandshakeTimeout: 15 * time.Second}
	conn, resp, err := dialer.DialContext(ctx, wssURL, header)
	if err != nil {
		if resp != nil {
			return nil, fmt.Errorf("edge tts 握手失败: status=%d: %w", resp.StatusCode, err)
		}
		return nil, fmt.Errorf("edge tts 连接失败: %w", err)
	}
	defer conn.Close()

	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetWriteDeadline(deadline)
		_ = conn.SetReadDeadline(deadline)
	} else {
		_ = conn.SetWriteDeadline(time.Now().Add(60 * time.Second))
		_ = conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	}

	configMsg := "X-Timestamp:" + edgeDateString() + "\r\n" +
		"Content-Type:application/json; charset=utf-8\r\n" +
		"Path:speech.config\r\n\r\n" +
		`{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"` +
		edgeOutputFormat + `"}}}}`
	if err := conn.WriteMessage(websocket.TextMessage, []byte(configMsg)); err != nil {
		return nil, fmt.Errorf("edge tts 发送配置失败: %w", err)
	}

	ssml := mkEdgeSSML(text, voice, rate, pitch, volume)
	ssmlMsg := "X-RequestId:" + edgeHexID() + "\r\n" +
		"Content-Type:application/ssml+xml\r\n" +
		"X-Timestamp:" + edgeDateString() + "Z\r\n" +
		"Path:ssml\r\n\r\n" + ssml
	if err := conn.WriteMessage(websocket.TextMessage, []byte(ssmlMsg)); err != nil {
		return nil, fmt.Errorf("edge tts 发送 ssml 失败: %w", err)
	}

	var audio bytes.Buffer
	for {
		msgType, data, err := conn.ReadMessage()
		if err != nil {
			return nil, fmt.Errorf("edge tts 读取失败: %w", err)
		}

		switch msgType {
		case websocket.TextMessage:
			// 文本消息为控制帧，收到 turn.end 表示本次合成结束。
			if strings.Contains(string(data), "Path:turn.end") {
				if audio.Len() == 0 {
					return nil, fmt.Errorf("edge tts 未返回音频数据")
				}
				return audio.Bytes(), nil
			}
		case websocket.BinaryMessage:
			// 二进制音频帧：前 2 字节为大端头部长度，之后是头部，再之后是音频数据。
			if len(data) < 2 {
				continue
			}
			headerLen := int(binary.BigEndian.Uint16(data[:2]))
			if 2+headerLen > len(data) {
				continue
			}
			audio.Write(data[2+headerLen:])
		}
	}
}

// edgeSecMSGEC 生成 Sec-MS-GEC 令牌。
// 必须与 edge-tts 的算法逐位一致（用 float64 运算，含大数浮点精度）：
// 取当前 Unix 秒 + 1601 纪元偏移，向下取整到 5 分钟（秒级），再换算成 100ns 计，
// 与固定 token 拼接后做 SHA256，大写十六进制。
func edgeSecMSGEC() string {
	const winEpochOffsetSec = 11644473600.0 // 1601-01-01 到 1970-01-01 的秒数
	ticks := float64(time.Now().Unix()) + winEpochOffsetSec
	ticks -= math.Mod(ticks, 300.0) // 向下取整到 5 分钟（300 秒）
	ticks *= 1e9 / 100.0            // 秒 -> 100ns
	str := strconv.FormatFloat(ticks, 'f', 0, 64)
	sum := sha256.Sum256([]byte(str + edgeTrustedClientToken))
	return strings.ToUpper(hex.EncodeToString(sum[:]))
}

func edgeDateString() string {
	return time.Now().UTC().Format("Mon Jan 02 2006 15:04:05 GMT+0000 (Coordinated Universal Time)")
}

func edgeHexID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return fmt.Sprintf("%032x", time.Now().UnixNano())
	}
	return hex.EncodeToString(b)
}

func mkEdgeSSML(text, voice, rate, pitch, volume string) string {
	return "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>" +
		"<voice name='" + voice + "'>" +
		"<prosody pitch='" + pitch + "' rate='" + rate + "' volume='" + volume + "'>" +
		xmlEscapeText(strings.TrimSpace(text)) +
		"</prosody></voice></speak>"
}
