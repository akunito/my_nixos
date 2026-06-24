"""Convert Plane rich-text (description_html) to Markdown for OpenProject."""
import html2text


def html_to_markdown(html: str) -> str:
    if not html:
        return ""
    h = html2text.HTML2Text()
    h.body_width = 0          # don't hard-wrap
    h.ignore_images = False
    h.ignore_links = False
    h.protect_links = True
    h.unicode_snob = True
    return h.handle(html).strip()
