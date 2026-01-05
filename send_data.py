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

if __name__ == "__main__":
    body = '{"name":"test","value":123}'
    message = (
        f"POST /api/data HTTP/1.1\r\n"
        f"Host: localhost:42069\r\n"
        f"Content-Type: application/json\r\n"
        f"Content-Length: {len(body)}\r\n"
        f"\r\n"
        f"{body}"
    )

    send_data_slowly(message, chunk_size=5, delay=2, close_early=False)



