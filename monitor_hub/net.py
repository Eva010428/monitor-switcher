LOCAL_HOSTS = {"127.0.0.1", "localhost", "::1"}


def bind_host(config_host: str | None) -> str:
    host = config_host or "0.0.0.0"
    if host in LOCAL_HOSTS:
        return host
    return "0.0.0.0"
