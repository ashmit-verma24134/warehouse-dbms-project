from flask import Flask

app = Flask(__name__)

@app.route("/")
def home():
    return "Warehouse Management System – Backend Running"

@app.route("/health")
def health():
    return "DB pending", 200

if __name__ == "__main__":
    app.run(debug=True)
