import socket
import sys
import time
import select

def send_data_slowly(data: str, host: str = "127.0.0.1", port: int = 42069, chunk_size: int = 1, delay: float = 0.1, close_early: bool = False):
    """Send data to the Zig TCP server slowly, chunk by chunk.

    If close_early is True, closes the connection after sending 20 bytes.
    """
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.connect((host, port))

            data_bytes = data.encode('utf-8')
            total_sent = 0

            for i in range(0, len(data_bytes), chunk_size):
                chunk = data_bytes[i:i + chunk_size]
                sock.send(chunk)
                total_sent += len(chunk)
                print(f"Sent: {chunk!r}")

                if close_early and total_sent >= 20:
                    print(f"\n[!] Closing connection early after {total_sent} bytes!")
                    return

                time.sleep(delay)

            print(f"\nTotal: {total_sent} bytes to {host}:{port}")

            # Signal we're done sending (half-close)
            sock.shutdown(socket.SHUT_WR)
            print("Shutdown write side")

            # Read the response using select
            sock.setblocking(False)
            for i in range(50):  # Try for 5 seconds
                readable, _, _ = select.select([sock], [], [], 0.1)
                if readable:
                    try:
                        response = sock.recv(4096)
                        if response:
                            print(f"\nResponse ({len(response)} bytes):\n{response.decode('utf-8')}")
                            return
                        else:
                            print("Connection closed by server (empty recv)")
                            return
                    except BlockingIOError:
                        continue
                print(f"Waiting... ({i+1})")

            print("Timeout - no response received")


    except ConnectionRefusedError:
        print(f"Error: Could not connect to {host}:{port}. Is the Zig server running?")
        sys.exit(1)


def receive_chunked_data(path: str = "/httpbin/stream/5", host: str = "127.0.0.1", port: int = 42069):
    """Request data from the Zig server and read chunked transfer encoding response.

    Reads chunks in format: <size in hex>\r\n<data>\r\n
    Until final chunk: 0\r\n\r\n
    """
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.connect((host, port))

            # Send GET request
            request = (
                f"GET {path} HTTP/1.1\r\n"
                f"Host: {host}:{port}\r\n"
                f"Connection: close\r\n"
                f"\r\n"
            )
            sock.send(request.encode('utf-8'))
            print(f"Sent request to {path}\n")

            # Read response headers
            response_data = b""
            while b"\r\n\r\n" not in response_data:
                chunk = sock.recv(1024)
                if not chunk:
                    break
                response_data += chunk

            header_end = response_data.find(b"\r\n\r\n")
            headers = response_data[:header_end].decode('utf-8')
            print(f"Response headers:\n{headers}\n")
            print("-" * 40)

            # Check if chunked
            if "transfer-encoding: chunked" not in headers.lower():
                print("Response is not chunked, reading normally...")
                body = response_data[header_end + 4:]
                while True:
                    chunk = sock.recv(4096)
                    if not chunk:
                        break
                    body += chunk
                print(f"Body: {body.decode('utf-8')}")
                return

            # Parse chunked body
            body_data = response_data[header_end + 4:]
            chunk_num = 0
            total_received = 0

            while True:
                # Read more data if needed
                while b"\r\n" not in body_data:
                    more = sock.recv(1024)
                    if not more:
                        break
                    body_data += more

                # Parse chunk size
                line_end = body_data.find(b"\r\n")
                if line_end == -1:
                    break

                size_line = body_data[:line_end].decode('utf-8').strip()
                chunk_size = int(size_line, 16)

                if chunk_size == 0:
                    print(f"\nReceived final chunk (size=0)")
                    break

                # Read chunk data
                body_data = body_data[line_end + 2:]
                while len(body_data) < chunk_size + 2:
                    more = sock.recv(1024)
                    if not more:
                        break
                    body_data += more

                chunk_content = body_data[:chunk_size]
                body_data = body_data[chunk_size + 2:]  # Skip \r\n after data

                chunk_num += 1
                total_received += chunk_size
                print(f"Chunk {chunk_num}: size={chunk_size} (0x{chunk_size:x})")
                print(f"  Data: {chunk_content.decode('utf-8', errors='replace')}")

            print(f"\nTotal received: {total_received} bytes in {chunk_num} chunks")

    except ConnectionRefusedError:
        print(f"Error: Could not connect to {host}:{port}. Is the Zig server running?")
        sys.exit(1)


if __name__ == "__main__":
    # Example 1: Send data slowly (original behavior)
    # body = '{"name":"test","value":123}'
    # message = (
    #     f"POST /api/data HTTP/1.1\r\n"
    #     f"Host: localhost:42069\r\n"
    #     f"Content-Type: application/json\r\n"
    #     f"Content-Length: {len(body)}\r\n"
    #     f"\r\n"
    #     f"{body}"
    # )
    # send_data_slowly(message, chunk_size=5, delay=2, close_early=False)

    # Example 2: Receive chunked data from server
    receive_chunked_data(path="/httpbin/stream/3")



