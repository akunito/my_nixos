import re
import markdown
from image_resolver import ImageResolver

# Regex patterns for Obsidian syntax
FRONTMATTER_RE = re.compile(r'^---\s*\n.*?\n---\s*\n', re.DOTALL)
KANBAN_SETTINGS_RE = re.compile(r'%%\s*kanban:settings\s*\n.*?\n%%', re.DOTALL)
COLOR_RE = re.compile(r'~=\{(\w+)\}(.*?)=~', re.DOTALL)
EMBED_RE = re.compile(r'!\[\[([^|\]]+?)(?:\|([^\]]*))?\]\]')
WIKILINK_RE = re.compile(r'\[\[([^\]]+?)\]\]')
CHECKBOX_CHECKED_RE = re.compile(r'^(\s*)- \[x\] ', re.MULTILINE)
CHECKBOX_UNCHECKED_RE = re.compile(r'^(\s*)- \[ \] ', re.MULTILINE)

WIKILINK_PLACEHOLDER = "{{WIKILINK:%s}}"


class ObsidianConverter:
    def __init__(self, image_resolver: ImageResolver = None):
        self.image_resolver = image_resolver or ImageResolver()
        self.md = markdown.Markdown(extensions=[
            "tables",
            "fenced_code",
            "codehilite",
            "nl2br",
        ])

    def convert(self, text: str) -> tuple[str, bool]:
        """Convert Obsidian markdown to HTML.

        Returns (html, has_wikilinks).
        """
        has_wikilinks = False

        # 1. Strip frontmatter
        text = FRONTMATTER_RE.sub("", text)

        # 2. Strip kanban settings
        text = KANBAN_SETTINGS_RE.sub("", text)

        # 3. Convert color text
        text = self._convert_colors(text)

        # 4. Convert embedded images
        text = self._convert_embeds(text)

        # 5. Convert wikilinks to placeholders
        if WIKILINK_RE.search(text):
            has_wikilinks = True
            text = self._convert_wikilinks(text)

        # 6. Convert checkboxes
        text = self._convert_checkboxes(text)

        # 7. Convert markdown to HTML
        self.md.reset()
        html = self.md.convert(text)

        return html, has_wikilinks

    def _convert_colors(self, text: str) -> str:
        return COLOR_RE.sub(r'<span style="color: \1">\2</span>', text)

    def _convert_embeds(self, text: str) -> str:
        def replacer(match):
            filename = match.group(1).strip()
            pipe_value = match.group(2)
            url = self.image_resolver.resolve(filename)

            if pipe_value and pipe_value.strip().isdigit():
                width = pipe_value.strip()
                return f'<img src="{url}" width="{width}" alt="{filename}" />'
            elif pipe_value:
                alt = pipe_value.strip()
                return f'<img src="{url}" alt="{alt}" />'
            else:
                return f'<img src="{url}" alt="{filename}" />'

        return EMBED_RE.sub(replacer, text)

    def _convert_wikilinks(self, text: str) -> str:
        def replacer(match):
            target = match.group(1)
            # Handle display text: [[target|display]]
            if "|" in target:
                target, display = target.split("|", 1)
            else:
                display = target.split("/")[-1]
            return WIKILINK_PLACEHOLDER % f"{target}|{display}"

        return WIKILINK_RE.sub(replacer, text)

    def _convert_checkboxes(self, text: str) -> str:
        text = CHECKBOX_CHECKED_RE.sub(
            r'\1- <input type="checkbox" checked disabled /> ', text)
        text = CHECKBOX_UNCHECKED_RE.sub(
            r'\1- <input type="checkbox" disabled /> ', text)
        return text


def convert_excalidraw(text: str, filename: str, nextcloud_url: str) -> str:
    """Convert Excalidraw file to a simple HTML page with text elements."""
    # Extract text between ## Text Elements and ## Drawing (or end)
    text_section = ""
    in_text = False
    lines = text.split("\n")
    for line in lines:
        if line.strip().startswith("## Text Elements"):
            in_text = True
            continue
        if in_text and line.strip().startswith("## "):
            break
        if in_text:
            text_section += line + "\n"

    html = "<h2>Diagram Text Elements</h2>\n"
    if text_section.strip():
        html += f"<pre>{text_section.strip()}</pre>\n"
    else:
        html += "<p><em>No text elements extracted.</em></p>\n"
    html += f'<p><strong>View original diagram:</strong> <a href="{nextcloud_url}">{filename}</a></p>'
    return html
