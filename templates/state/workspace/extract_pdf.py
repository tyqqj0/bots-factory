#!/usr/bin/env python3
import PyPDF2
import sys

pdf_file = sys.argv[1] if len(sys.argv) > 1 else "epiplexity_paper.pdf"

with open(pdf_file, 'rb') as file:
    pdf_reader = PyPDF2.PdfReader(file)
    text = ""
    for page in pdf_reader.pages[:15]:  # 只读前15页
        text += page.extract_text()
    print(text)
