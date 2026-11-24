"""Entry point: ``python3 -I -m framac_mcp`` / the ``framac-mcp`` console script."""

from .server import main

if __name__ == "__main__":
    raise SystemExit(main())
