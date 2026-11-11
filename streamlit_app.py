"""Timeline Restorer: Back in Time — Streamlit wrapper.

The game itself is a single self-contained HTML file
(timeline-restorer/timeline-restorer.html, zero external dependencies).
This app embeds it full-width via Streamlit's HTML component. All game
state (including localStorage saves) lives inside the embedded page.
"""

from pathlib import Path

import streamlit as st
import streamlit.components.v1 as components

GAME_FILE = Path(__file__).parent / "timeline-restorer" / "timeline-restorer.html"

st.set_page_config(
    page_title="Timeline Restorer: Back in Time",
    page_icon="⏳",
    layout="wide",
    initial_sidebar_state="collapsed",
)

st.markdown(
    """
    <style>
        /* Give the game the whole viewport. */
        .block-container { padding-top: 0.5rem; padding-bottom: 0rem; }
        header[data-testid="stHeader"] { display: none; }
    </style>
    """,
    unsafe_allow_html=True,
)

if not GAME_FILE.is_file():
    st.error(
        "Game file not found: `timeline-restorer/timeline-restorer.html` "
        "is missing from this repo."
    )
    st.stop()

html = GAME_FILE.read_text(encoding="utf-8")
components.html(html, height=900, scrolling=True)

st.caption(
    "Tip: use your browser's zoom or the in-game controls — "
    "Truth Check, Inventory, Save/Load, and Ctrl+Shift+D for the debug console. "
    "Saves are stored in this browser."
)
