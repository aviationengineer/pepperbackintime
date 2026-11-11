"""Timeline Restorer: Back in Time — v2 (Phaser 3) Streamlit wrapper.

Serves the v2 game: timeline-restorer/v2/timeline-restorer.html, a single
self-contained file with Phaser 3.80.1 inlined (animated characters,
click-to-walk navigation, layered scenes, procedural music/SFX).
The v1 app (streamlit_app.py) serves the original version separately.
"""

from pathlib import Path

import streamlit as st
import streamlit.components.v1 as components

GAME_FILE = Path(__file__).parent / "timeline-restorer" / "v2" / "timeline-restorer.html"

st.set_page_config(
    page_title="Timeline Restorer: Back in Time — v2",
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
        "Game file not found: `timeline-restorer/v2/timeline-restorer.html` "
        "is missing from this repo."
    )
    st.stop()

html = GAME_FILE.read_text(encoding="utf-8")
components.html(html, height=900, scrolling=True)

st.caption(
    "v2 — Phaser edition: walk the Time Cadet with a click, talk to "
    "characters, and follow the music. Truth Check, Inventory, Save/Load, "
    "and Ctrl+Shift+D for the debug console. Saves are stored in this browser."
)
